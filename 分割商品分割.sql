ALTER PROCEDURE [dbo].[rj_Batch_ComArticleSplit]
  @rq [datetime]
AS
BEGIN
  /*********************************************************
  把待处理组合商品拆出成分
  版本 1.1
  -----------------------------------------------------------------
  1.0 仅支持销售拆分
  -----------------------------------------------------------------
  1.1 2019-06-21
  发现可能会有组合商品成分表暂时没有记录的问题，增加判断，如果tPosSaleCost打了标记，但是tComplexElement没记录的，报错
  *********************************************************/

  /* 先获取组合商品的明细 */
  SELECT
    sStoreNO,
    dDealDate,
      dTradeDate = dBatchDate,
    sPaperNO,
      sPosNO = substring(sPaperNO, 1, 3),
      nSerID = convert(NUMERIC(4), substring(sPaperNO, 4, 4)),
      nItem = convert(NUMERIC(3), substring(sPaperNO, 8, 3)),
    nGoodsID
  INTO #c01
  FROM rj_TmpBatch
  WHERE dDealDate = @rq AND nLeftQty <> 0 AND nLeftQty = nQty /* 这是保证未处理过的 */
        AND nBatchID IS NULL AND sBatchTypeID IN ('3', '10')
        AND len(sPaperNO) = 10

  SELECT
    a.nGoodsID,
      nQty = sum(b.nSaleQty)
  INTO #c02
  FROM #c01 AS a, tPosSaleCost AS b
  WHERE a.sStoreNO = b.sStoreNO AND a.dTradeDate = b.dTradeDate AND a.sPosNO = b.sPosNO AND a.nSerID = b.nSerID
        AND a.nGoodsID = b.nGoodsID AND b.sMemo = '组合商品已拆分'
  GROUP BY a.nGoodsID

  DELETE FROM #c02 FROM #c02 AS a, tComplexElement AS b
  WHERE a.nGoodsID = b.nGoodsID AND b.nTag & 1 = 0

  IF exists(SELECT 1
            FROM #c02)
    BEGIN
      DECLARE @errmsg VARCHAR(100)
      SELECT @errmsg = '商品ID=' + convert(VARCHAR, nGoodsID) + '，标识为组合商品，但是组合成分表现在没记录，请检查！'
      FROM #c02
      RAISERROR (@errmsg, 16, 1)
      RETURN
    END

  DROP TABLE #c01
  DROP TABLE #c02

  SELECT
    sStoreNO,
    a.dDealDate,
    a.dBatchDate,
    a.sPaperNO,
    a.nGoodsID,
    b.nElementID,
    a.ID,
    a.sBatchTypeID,
      nSaleQty = CASE WHEN a.sBatchTypeID = '3'
      THEN -1
                 ELSE 1 END * a.nQty,
      nSaleAmount = CASE WHEN a.sBatchTypeID = '3'
        THEN -1
                    ELSE 1 END * a.nAmount,
      nSubQty = convert(NUMERIC(12, 3), CASE WHEN a.sBatchTypeID = '3'
        THEN -1
                                        ELSE 1 END * a.nQty * b.nQty),
      nSubAmount = convert(NUMERIC(16, 2), CASE WHEN a.sBatchTypeID = '3'
        THEN -1
                                           ELSE 1 END * a.nAmount * b.nQty),
      nRatio = convert(NUMERIC(8, 4), 0),
      nSalePrice = convert(NUMERIC(12, 2), round(a.nAmount / a.nQty, 2)),
      nID = identity(INT)
  INTO #c1
  FROM rj_TmpBatch AS a, tGoods AS g, tComplexElement AS b
  WHERE a.dDealDate = @rq AND a.nLeftQty <> 0 AND a.nLeftQty = a.nQty /* 这是保证未处理过的 */
        AND a.nBatchID IS NULL
        AND a.sBatchTypeID IN ('3', '10')
        AND a.nGoodsID = g.nGoodsID AND g.sGoodTypeID = 'C' AND a.nGoodsID = b.nGoodsID AND b.nTag & 1 = 0

  IF NOT exists(SELECT 1
                FROM #c1)
    BEGIN
      DROP TABLE #c1
      RETURN
    END

  UPDATE #c1
  SET nSalePrice = b.nRealSalePrice FROM #c1 AS a, tStoreGoods AS b
  WHERE a.sStoreNO = b.sStoreNO AND a.nElementID = b.nGoodsID

  /* 计算一下售价总金额 */
  SELECT
    sStoreNO,
    ID,
    nGoodsID,
      nSaleQty = max(nSaleQty),
      nSubAmount = convert(NUMERIC(16, 2), sum(round(nSubQty * nSalePrice, 2)))
  INTO #c2
  FROM #c1
  GROUP BY sStoreNO, ID, nGoodsID

  -- select * from #c2

  /* 计算比例 */
  UPDATE #c1
  SET nRatio = round(round(a.nSubQty * a.nSalePrice, 2) / b.nSubAmount, 4)
  FROM #c1 AS a, #c2 AS b
  WHERE a.ID = b.ID

  /* 根据售价比例计算每条明细的销售金额 */
  UPDATE #c1
  SET nSubAmount = round(nRatio * nSaleAmount, 2)

  /* 有差异的，更新到最小一条记录 */
  UPDATE #c1
  SET nSubAmount = a.nSubAmount + b.nDiffAmount
  FROM #c1 AS a, (SELECT
                    ID,
                      nID = min(nID),
                      nDiffAmount = max(nSaleAmount) - sum(nSubAmount)
                  FROM #c1
                  GROUP BY ID
                  HAVING max(nSaleAmount) <> sum(nSubAmount)
                 ) AS b
  WHERE a.ID = b.ID AND a.nID = b.nID

  DECLARE @err INT = 0, @rc INT
  SELECT @rc = count(*)
  FROM #c2

  BEGIN TRAN
  /* 把原来的组合商品的记录，弄成0 */
  UPDATE rj_TmpBatch
  SET nRetQty = nQty, nPrice1 = nAmount, nQty = 0, nAmount = 0,
    nLeftQty  = 0, nLeftAmount = 0, sContractNO = '组合商品已拆分'
  FROM rj_TmpBatch AS a, #c2 AS b
  WHERE a.ID = b.ID AND CASE WHEN a.sBatchTypeID = '3'
    THEN -1
                        ELSE 1 END * a.nLeftQty = b.nSaleQty
  IF @@rowcount <> @rc OR @@error <> 0
    BEGIN
      RAISERROR ('更新组合商品原带处理批次记录出错。', 16, 1)
      RETURN
    END

  /* 拆出来的子商品销售插回去 */
  INSERT INTO rj_TmpBatch (dDealDate, nBatchID, nGoodsID, nVendorID, sBatchTypeID, nQty,
                           nRetQty, nLeftQty, nAmount,
                           nLeftAmount, nBatchPrice, dBatchDate, sPaperNO, sStoreNO,
                           dLastUpdateTime, nPrice1, sContractNO, sTradeModeID, nTaxPct, sLocatorNO, sInspectNO,
                           sDeclarationNO, sCertificateOfOriginNO, dProduceDate, nStatus, sOption)
    SELECT
      dDealDate,
      NULL,
      nElementID,
      NULL,
      sBatchTypeID,
      CASE WHEN a.sBatchTypeID = '3'
        THEN -1
      ELSE 1 END * nSubQty,
      0,
      CASE WHEN a.sBatchTypeID = '3'
        THEN -1
      ELSE 1 END * nSubQty,
      CASE WHEN a.sBatchTypeID = '3'
        THEN -1
      ELSE 1 END * nSubAmount,
      CASE WHEN a.sBatchTypeID = '3'
        THEN -1
      ELSE 1 END * nSubAmount,
      NULL,
      dBatchDate,
      sPaperNO,
      sStoreNO,
      getdate(),
      ID,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      '组合成分'
    FROM #c1 AS a
  IF @@error <> 0
    ROLLBACK TRAN
  ELSE COMMIT TRAN

  DROP TABLE #c1
  DROP TABLE #c2
END