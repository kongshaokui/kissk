ALTER PROCEDURE [dbo].[rj_ContractDaily_DC]
  @rq    [datetime],
  @Force [int] = 0
AS
BEGIN
  /*****************************************
  配送中心合同商品日进销存汇总
  版本 3.1
  创建时间 2014-04-20
  -----------------------------------------
  2.0 改成 进销存分储位sLocatorNO
  -----------------------------------------
  rj_DealBatch的sBatchTypeID（仅列出和配送有关）
  2=进货，3=销售，5=库调增加，8=库调减少，4=退配（其实原来是调入），6=退货，21=移仓，24发货
  tContractGoodsDaily.sTypeID
  01=期初/期末，02=销售/成本，04=进货/发货，05=退货/退配，06=调入/调出，07=库调/系统调整，08=移仓/未使用，22=销售退货/退货成本
  -----------------------------------------
  2.1 修改 2015-06-24
  负库存的调整冲减，把临时储位放在rj_DealBatch的sDeclarationNO字段，增加处理
  增加判断，如果不是第一天做日结，那么只有前一天日结已经做了，才能进行本日日结
  --------------------------------------------------------------
  2.2 修改
  销售退货，因为模块用了退配形式入库，所以算到退配去了
  这里修正为和销售合并，同时另外加了一个类型22作为销售退货
  --------------------------------------------------------------
  2.3 修改  2015-12-20
  增加调拨支持，退配入库和调拨用的是同一种批次类型，
  所以在配送中心调拨的批次处理中使用了sTmpContarctNO='配送调拨'来标记
  同时增加批次记录和批次处理记录无储位号的检查
  --------------------------------------------------------------
  2.4 修改  2016-01-14
  多配送中心，前面取@dc的时候，有时候会取到不同的的店号，导致对日结状态判断出问题
  增加order by，按顺序取第一个
  --------------------------------------------------------------
  2.5 修改  2016-05-02
  调整明细增加店号是配送中心的处理
  --------------------------------------------------------------
  2.6 修改  2017-04-07
  计算系统调整的时候，加上调拨的判断
  有些地方增加判断是配送中心的分店才计算
  --------------------------------------------------------------
  2.7 修改  2017-06-27
  raiserror改成函数
  去掉tRunListStatus记录
  --------------------------------------------------------------
  2.8 修改  2017-06-28
  蔬果配送初期有没单据、没库存的情况，这样某天就没有进销存记录了，所以不能用这天有没有记录来判断有没有日结
  ---------------------------------------------
  2.9 修改 2018-06-25
  这是为BS模块写入rj_DealBatch的sBatchTypeID错误而做的修改，销售类型加上14，数量做正负判断，进货类型加上1
  还要把批次价从nRealBatchPrice从原始批次记录获取一次以便得到毛利，出货价保留在nTmpBatchPrice
  ---------------------------------------------
  3.0 修改 2019-01-30
  配送发货的，CS写rj_DealBatch.nQty是负的，BS是正的，干脆都先用ABS吧。
  ---------------------------------------------
  3.1 修改 2019-08-22
  退配做销售退货的，要改一下判断规则，原来用rj_DealBatch的nAmount，现在嘛，不好控制程序员怎么写值
  ****************************************/
  DECLARE @dc VARCHAR(16)
  SET ROWCOUNT 1
  SELECT @dc = sStoreNO
  FROM tStore
  WHERE sStoreTypeID = '3' AND nTag & 1 = 0
  ORDER BY sStoreNO
  SET ROWCOUNT 0

  IF exists(SELECT 1
            FROM tContractGoodsDaily_DC) AND NOT exists(SELECT 1
                                                        FROM tContractGoodsDaily_DC
                                                        WHERE dTradeDate = dateadd(DD, -1, @rq))
     AND NOT exists(SELECT 1
                    FROM tRunLog
                    WHERE dRunDate = dateadd(DD, -1, @rq) AND sProcNO = 'ContractDaily_DC' AND sMessageID = '执行成功！')
    BEGIN
      RAISERROR ('昨天日结没做！', 16, 1)
      RETURN
    END

  IF exists(SELECT 1
            FROM rj_DealBatch
            WHERE dDealDate = @rq AND isnull(sLocatorNO, '') = ''
                  AND sStoreNO IN (SELECT sStoreNO
                                   FROM tStore
                                   WHERE sStoreTypeID = '3' AND nTag & 1 = 0)
  )
    BEGIN
      RAISERROR ('存在无储位的批次处理记录！请检查！', 16, 1)
      RETURN
    END

  IF exists(SELECT 1
            FROM tStockBatch
            WHERE (nActionQty + nLockedQty - nPendingQty) <> 0 AND isnull(sLocatorNO, '') = ''
                  AND sStoreNO IN (SELECT sStoreNO
                                   FROM tStore
                                   WHERE sStoreTypeID = '3' AND nTag & 1 = 0)
  )
    BEGIN
      RAISERROR ('存在无储位的tStockBatch记录！请检查！', 16, 1)
      RETURN
    END

  CREATE TABLE #dcs (
    sStoreNO VARCHAR(20)
  )
  INSERT INTO #dcs SELECT sStoreNO
                   FROM tStore
                   WHERE sStoreTypeID = '3' AND nTag & 1 = 0

  IF exists(SELECT 1
            FROM rj_DealBatch
            WHERE dDealDate = @rq AND sBatchTypeID = '14' AND nAmount IS NOT NULL
                  AND sStoreNO IN (SELECT sStoreNO
                                   FROM #dcs))
    BEGIN
      SELECT
        ID,
        nBatchID,
        nGoodsID,
        sStoreNO,
        sContractNO,
          nRealBatchPrice = convert(NUMERIC(16, 4), NULL)
      INTO #rd1
      FROM rj_DealBatch
      WHERE dDealDate = @rq AND sBatchTypeID = '14' AND nAmount IS NOT NULL
            AND sStoreNO IN (SELECT sStoreNO
                             FROM #dcs)

      UPDATE #rd1
      SET nRealBatchPrice = b.nBatchPrice FROM #rd1 AS a, tStockBatch AS b
      WHERE a.sStoreNO = b.sStoreNO AND a.nBatchID = b.nBatchID AND a.nGoodsID = b.nGoodsID
      IF exists(SELECT 1
                FROM #rd1
                WHERE nRealBatchPrice IS NULL)
        BEGIN
          UPDATE #rd1
          SET nRealBatchPrice = b.nRealBatchPrice FROM #rd1 AS a, rj_DealBatch AS b
          WHERE a.sStoreNO = b.sStoreNO AND a.nBatchID = b.nBatchID AND a.nGoodsID = b.nGoodsID AND
                a.nRealBatchPrice IS NULL AND b.sBatchTypeID IN ('1', '2', '13', '4', '5')
        END
      IF exists(SELECT 1
                FROM #rd1
                WHERE nRealBatchPrice IS NULL)
        BEGIN
          UPDATE #rd1
          SET nRealBatchPrice = b.nRealBatchPrice FROM #rd1 AS a, His_DealBatch AS b
          WHERE a.sStoreNO = b.sStoreNO AND a.nBatchID = b.nBatchID AND a.nGoodsID = b.nGoodsID AND
                b.sBatchTypeID IN ('1', '2', '13', '7', '5')
                AND a.nRealBatchPrice IS NULL AND b.dDealDate >= DATEADD(MM, -3, @rq)
        END

      UPDATE rj_DealBatch
      SET nRealBatchPrice = b.nRealBatchPrice FROM rj_DealBatch AS a, #rd1 AS b
      WHERE a.ID = b.ID AND b.nRealBatchPrice IS NOT NULL

      DROP TABLE #rd1

    END

  CREATE TABLE #Daily1 (
    dTradeDate   DATETIME,
    sStoreNO     VARCHAR(4),
    sContractNO  VARCHAR(20),
    nGoodsID     NUMERIC(8),
    sLocatorNO   VARCHAR(20),
    nVendorID    NUMERIC(8),
    sTypeID      VARCHAR(4),
    sType        VARCHAR(20),
    nTaxPct      NUMERIC(8, 5),
    nQty1        NUMERIC(12, 3),
    nAmount1     NUMERIC(12, 2),
    nNetAmount1  NUMERIC(12, 2),
    nQty2        NUMERIC(12, 3),
    nAmount2     NUMERIC(12, 2),
    nNetAmount2  NUMERIC(12, 2),
    sCategoryNO  VARCHAR(8),
    sTradeModeID VARCHAR(4),
    nSalePrice   NUMERIC(12, 2) NULL,
    sPRSTypeID   VARCHAR(4)     NULL
  )

  CREATE TABLE #Daily2 (
    dTradeDate       DATETIME,
    sStoreNO         VARCHAR(4),
    sContractNO      VARCHAR(20),
    nGoodsID         NUMERIC(8),
    sLocatorNO       VARCHAR(20),
    nVendorID        NUMERIC(8),
    nTaxPct          NUMERIC(8, 5),
    nBeginQty        NUMERIC(12, 3),
    nBeginAmount     NUMERIC(12, 2),
    nBeginNetAmount  NUMERIC(12, 2),
    nEndQty          NUMERIC(12, 3),
    nEndAmount       NUMERIC(12, 2),
    nEndNetAmount    NUMERIC(12, 2),
    nInQty           NUMERIC(12, 3),
    nInAmount        NUMERIC(12, 2),
    nInNetAmount     NUMERIC(12, 2),
    nOutQty          NUMERIC(12, 3),
    nOutAmount       NUMERIC(12, 2),
    nOutNetAmount    NUMERIC(12, 2),
    nSysAdjQty       NUMERIC(12, 3),
    nSysAdjAmount    NUMERIC(12, 2),
    nSysAdjNetAmount NUMERIC(12, 2),
    sTradeModeID     VARCHAR(2)
  )
  CREATE TABLE #Daily3 (
    dTradeDate       DATETIME,
    sStoreNO         VARCHAR(4),
    sContractNO      VARCHAR(20),
    nGoodsID         NUMERIC(8),
    sLocatorNO       VARCHAR(20),
    nVendorID        NUMERIC(8),
    nTaxPct          NUMERIC(8, 5),
    nBeginQty        NUMERIC(12, 3),
    nBeginAmount     NUMERIC(12, 2),
    nBeginNetAmount  NUMERIC(12, 2),
    nEndQty          NUMERIC(12, 3),
    nEndAmount       NUMERIC(12, 2),
    nEndNetAmount    NUMERIC(12, 2),
    nInQty           NUMERIC(12, 3),
    nInAmount        NUMERIC(12, 2),
    nInNetAmount     NUMERIC(12, 2),
    nOutQty          NUMERIC(12, 3),
    nOutAmount       NUMERIC(12, 2),
    nOutNetAmount    NUMERIC(12, 2),
    nSysAdjQty       NUMERIC(12, 3),
    nSysAdjAmount    NUMERIC(12, 2),
    nSysAdjNetAmount NUMERIC(12, 2),
    sTradeModeID     VARCHAR(2),
    PRIMARY KEY (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nTaxPct)
  )
  CREATE TABLE #Batch (
    sStoreNO     VARCHAR(4),
    nVendorID    NUMERIC(8),
    nGoodsID     NUMERIC(8),
    sLocatorNO   VARCHAR(20),
    nBatchQty    NUMERIC(12, 3),
    nBatchPrice  NUMERIC(12, 4),
    nTaxPct      NUMERIC(8, 5),
    sContractNO  VARCHAR(20),
    sTradeModeID VARCHAR(2)
  )
  CREATE TABLE #EndStock (
    sStoreNO      VARCHAR(4),
    sContractNO   VARCHAR(20),
    nGoodsID      NUMERIC(8),
    sLocatorNO    VARCHAR(20),
    nVendorID     NUMERIC(8),
    nTaxPct       NUMERIC(8, 5),
    nEndQty       NUMERIC(12, 3),
    nEndAmount    NUMERIC(12, 2),
    nEndNetAmount NUMERIC(12, 2),
    sTradeModeID  VARCHAR(2)
  )

  /* 期初 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2,
                       sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nVendorID,
      '01',
      '期初/期末',
      nTaxPct,
      nQty2,
      nAmount2,
      nNetAmount2,
      0,
      0,
      0,
      sCategoryNO,
      sTradeModeID,
      NULL,
      NULL
    FROM tContractGoodsDaily_DC
    WHERE dTradeDate = dateadd(DD, -1, @rq) AND sTypeID = '01' AND (nQty2 <> 0 OR nAmount2 <> 0)

  /****************************************************************************
  按照批次处理记录的进销存   begin
  *****************************************************************************/
  /* 汇总销售 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                                    AS nVendorID,
      '02',
      '销售/成本',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(CASE WHEN sBatchTypeID = '14'
        THEN 1
                                  ELSE -1 END * nQty))                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(CASE WHEN sBatchTypeID = '14'
        THEN 1
                                  ELSE -1 END * nAmount))                                              AS nSaleAmount,
      convert(NUMERIC(12, 2), sum(round(CASE WHEN sBatchTypeID = '14'
        THEN 1
                                        ELSE -1 END * nAmount / nTaxPct,
                                        2)))                                                           AS nSaleNetAmount,
      convert(NUMERIC(12, 3), sum(CASE WHEN sBatchTypeID = '14'
        THEN 1
                                  ELSE -1 END * nQty))                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(round(CASE WHEN sBatchTypeID = '14'
        THEN 1
                                        ELSE -1 END * nQty * nRealBatchPrice, 2)))                     AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(CASE WHEN sBatchTypeID = '14'
        THEN 1
                                              ELSE -1 END * nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('3', '14') AND nType < 2
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 2.2 销售退货 begin ***********************************************************/
  SELECT
    dDealDate,
    TmpID,
    nGoodsID,
    nRealVendorID,
    nQty,
    nAmount,
    nRealBatchPrice,
    sStoreNO,
    sContractNO,
    sTradeModeID,
    nTaxPct,
    sLocatorNO,
      sRetDCPaperNO = CONVERT(VARCHAR(16), NULL),
      sPaperNO = CONVERT(VARCHAR(16), NULL),
      sCustNO = CONVERT(VARCHAR(20), NULL),
      nIsSaleRet = 0
  INTO #ret1
  FROM rj_DealBatch
  WHERE dDealDate = @rq AND sBatchTypeID = '4' AND nType < 2
        AND sStoreNO IN (SELECT sStoreNO
                         FROM #dcs)

  /* 获取退配单号 */
  UPDATE #ret1
  SET sRetDCPaperNO = b.sPaperNO FROM #ret1 AS a, rj_TmpBatch AS b
  WHERE a.TmpID = b.ID

  /* 获取退货单号 */
  UPDATE #ret1
  SET sPaperNO = b.sOrderNO, sCustNO = b.sFromStoreNO, nIsSaleRet = 1
  FROM #ret1 AS a, tWithoutTransfer AS b
  WHERE a.sStoreNO = b.sToStoreNO AND a.sRetDCPaperNO = b.sPaperNO
        AND b.sTplType = '销售退配单'

  /* 获取退货金额 */
  UPDATE #ret1
  SET nAmount = ROUND(b.nSaleQty * b.nDealPrice, 2)
  FROM #ret1 AS a, tWholesale_D AS b
  WHERE a.sStoreNO = b.sStoreNO AND a.sPaperNO = b.sPaperNO
        AND a.nGoodsID = b.nGoodsID

  /* 不是退货的删掉 */
  DELETE FROM #ret1
  WHERE nIsSaleRet = 0

  /* 插入退货 -- 和销售合并 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                       AS nVendorID,
      '02',
      '销售/成本',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(-nAmount))                                              AS nSaleAmount,
      convert(NUMERIC(12, 2), sum(-round(nAmount / nTaxPct, 2)))                          AS nSaleNetAmount,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(-round(nQty * nRealBatchPrice, 2)))                     AS nSaleCost,
      convert(NUMERIC(12, 2), sum(-round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM #ret1
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 插入退货 -- 独立退货 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                       AS nVendorID,
      '22',
      '销售退货/退货成本',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(-nAmount))                                              AS nSaleAmount,
      convert(NUMERIC(12, 2), sum(-round(nAmount / nTaxPct, 2)))                          AS nSaleNetAmount,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(-round(nQty * nRealBatchPrice, 2)))                     AS nSaleCost,
      convert(NUMERIC(12, 2), sum(-round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM #ret1
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 2.2 销售退货 end ***********************************************************/

  /* 汇总进货 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                      AS nVendorID,
      '04',
      '进货/配送',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(nQty))                                                 AS nAcptQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice, 2)))                     AS nAcptAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nAcptNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('1', '2', '12') AND nType < 2
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总发货 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                           AS nVendorID,
      '04',
      '进货/配送',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(abs(nQty)))                                                 AS nSendQty,
      convert(NUMERIC(12, 2), sum(round(abs(nQty) * nRealBatchPrice, 2)))                     AS nSendAmount,
      convert(NUMERIC(12, 2), sum(round(round(abs(nQty) * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSendNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('24')
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总配送红冲 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1,
                       nQty2, nAmount2, nNetAmount2,
                       sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                       AS nVendorID,
      '04',
      '进货/配送',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nDCOutQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice, 2)))                     AS nDCOutAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nDCOutNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID = '13' AND nType < 2
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总退货 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                       AS nVendorID,
      '05',
      '退货/退配',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nReturnQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice, 2)))                     AS nReturnAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nReturnNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID = '6' AND nType < 2
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总退配 (配送中心退配用的是调入的批次类型) */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1, nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                      AS nVendorID,
      '05',
      '退货/退配',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(nQty))                                                 AS nDCOutQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice, 2)))                     AS nDCOutAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nDCOutNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID = '4' AND nType < 2 AND isnull(sTmpContractNO, '') <> '配送调拨'
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
          /* 2.2 增加判断去掉销售退货部分 */
          AND TmpID NOT IN (SELECT DISTINCT TmpID
                            FROM #ret1)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总调入 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1, nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                      AS nVendorID,
      '06',
      '调入/调出',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(nQty))                                                 AS nTransInQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice, 2)))                     AS nTransInAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nTransInNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID = '4' AND nType < 2 AND isnull(sTmpContractNO, '') = '配送调拨'
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
          /* 2.2 增加判断去掉销售退货部分 */
          AND TmpID NOT IN (SELECT DISTINCT TmpID
                            FROM #ret1)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总调出 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1, nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                       AS nVendorID,
      '06',
      '调入/调出',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(-nQty))                                                 AS nTransOutQty,
      convert(NUMERIC(12, 2), sum(-round(nQty * nRealBatchPrice, 2)))                     AS nTransOutAmount,
      convert(NUMERIC(12, 2), sum(-round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nTransOutNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID = '7' AND nType < 2
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总调整 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                      AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(nQty))                                                 AS nAdjQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice, 2)))                     AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nAdjNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('5', '8') AND nType < 2
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 调整冲减-暂置调整减掉 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sTmpContractNO,
      nGoodsID,
      isnull(sDeclarationNO, sLocatorNO),
      nTmpVendorID                                                                       AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(-nQty))                                                AS nAdjQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nTmpBatchPrice, 2)))                     AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nTmpBatchPrice, 2) / nTaxPct, 2))) AS nAdjNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('5', '8') AND nType = 3
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sTmpContractNO, nGoodsID, isnull(sDeclarationNO, sLocatorNO), nTmpVendorID, nTaxPct

  /* 调整冲减-实际调整加进来 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                      AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(nQty))                                                 AS nAdjQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice, 2)))                     AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nAdjNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('5', '8') AND nType = 3
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 汇总移仓 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct,
                       nQty1, nAmount1,
                       nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                                                                      AS nVendorID,
      '08',
      '移仓/未使用',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(nQty))                                                 AS nMoveQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice, 2)))                     AS nMoveAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nMoveNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('21', '23')
          AND dDealDate = @rq
          AND sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct

  /* 调整明细 */
  SELECT
      sAdjType = convert(VARCHAR(3), ''),
    a.ID,
    a.sBatchTypeID,
    a.sStoreNO,
    a.nRealVendorID,
    a.nGoodsID,
    a.nQty,
    a.nRealBatchPrice,
    a.sContractNO,
    a.nTaxPct,
    a.sTmpContractNO,
    b.sPaperNO,
      sTmpBatchTypeID = b.sBatchTypeID,
      sOrgContractNO = b.sContractNO,
    a.sTradeModeID,
    a.sLocatorNO
  INTO #adjd1
  FROM rj_DealBatch AS a, rj_TmpBatch AS b
  WHERE a.dDealDate = @rq AND a.TmpID = b.ID AND a.sStoreNO = b.sStoreNO
        AND a.sBatchTypeID IN ('5', '8')
        AND a.sStoreNO IN (SELECT sStoreNO
                           FROM #dcs)
        AND a.nType < 2

  /* 收货更正 */
  UPDATE #adjd1
  SET sAdjType = '722'
  WHERE sAdjType = '' AND sTmpBatchTypeID = '12'

  /* 盘点损益/一般损益 */
  UPDATE #adjd1
  SET sAdjType = CASE WHEN b.sAdjustTypeId IN ('1', '2')
    THEN '711'
                 WHEN b.sAdjustTypeId IN ('3', '6')
                   THEN '712' END
  FROM #adjd1 AS a, tStockAdj AS b
  WHERE a.sAdjType = '' AND a.sTmpBatchTypeID IN ('5', '8') AND a.sStoreNO = b.sStoreNO AND a.sPaperNO = b.sPaperNO
        AND b.sAdjustTypeId IN ('1', '2', '3', '6')

  DELETE FROM #adjd1
  WHERE sAdjType = ''

  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID,
                       sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nRealVendorID                            AS nVendorID,
      substring(sAdjType, 1, 2),
      CASE substring(sAdjType, 1, 2)
      WHEN '71'
        THEN '盘点损益/一般损益'
      WHEN '72'
        THEN '批次转换/收货更正'
      WHEN '73'
        THEN '客商库调/生鲜分割'
      WHEN '74'
        THEN '退货改价/促销扣点' END,
      nTaxPct,
      convert(NUMERIC(12, 3), sum(CASE WHEN sAdjType IN ('711', '721', '731', '741')
        THEN nQty
                                  ELSE 0 END)) AS nQty1,
      convert(NUMERIC(12, 2), sum(CASE WHEN sAdjType IN ('711', '721', '731', '741')
        THEN round(nQty * nRealBatchPrice, 2)
                                  ELSE 0 END)) AS nAmount1,
      convert(NUMERIC(12, 2), sum(CASE WHEN sAdjType IN ('711', '721', '731', '741')
        THEN round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2)
                                  ELSE 0 END)) AS nNetAmount1,
      convert(NUMERIC(12, 3), sum(CASE WHEN sAdjType IN ('712', '722', '732', '742')
        THEN nQty
                                  ELSE 0 END)) AS nQty2,
      convert(NUMERIC(12, 2), sum(CASE WHEN sAdjType IN ('712', '722', '732', '742')
        THEN round(nQty * nRealBatchPrice, 2)
                                  ELSE 0 END)) AS nAmount2,
      convert(NUMERIC(12, 2), sum(CASE WHEN sAdjType IN ('712', '722', '732', '742')
        THEN round(round(nQty * nRealBatchPrice, 2) / nTaxPct, 2)
                                  ELSE 0 END)) AS nNetAmount2,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL
    FROM #adjd1
    WHERE sAdjType <> ''
    GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nRealVendorID, nTaxPct, substring(sAdjType, 1, 2),
      CASE substring(sAdjType, 1, 2)
      WHEN '71'
        THEN '盘点损益/一般损益'
      WHEN '72'
        THEN '批次转换/收货更正'
      WHEN '73'
        THEN '客商库调/生鲜分割'
      WHEN '74'
        THEN '退货改价/促销扣点' END

  /***********************************************************************************/
  /* 汇总弄到进销存临时表，准备计算系统调整，或者计算期末 */
  INSERT INTO #Daily3 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, nTaxPct, nBeginQty, nBeginAmount, nBeginNetAmount,
                       nEndQty, nEndAmount, nEndNetAmount, nInQty,
                       nInAmount,
                       nInNetAmount,
                       nOutQty,
                       nOutAmount,
                       nOutNetAmount,
                       nSysAdjQty, nSysAdjAmount, nSysAdjNetAmount, sTradeModeID)
    SELECT
      dTradeDate,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nVendorID,
      nTaxPct,
      sum(CASE WHEN sTypeID = '01'
        THEN nQty1
          ELSE 0 END),
      sum(CASE WHEN sTypeID = '01'
        THEN nAmount1
          ELSE 0 END),
      sum(CASE WHEN sTypeID = '01'
        THEN nNetAmount1
          ELSE 0 END),
      0,
      0,
      0,
        nInQty = sum(CASE WHEN sTypeID IN ('04', '06', '07', '08')
        THEN nQty1
                     ELSE 0 END + CASE WHEN sTypeID IN ('05')
        THEN nQty2
                                  ELSE 0 END),
        nInAmount = sum(CASE WHEN sTypeID IN ('04', '06', '07', '08')
          THEN nAmount1
                        ELSE 0 END + CASE WHEN sTypeID IN ('05')
          THEN nAmount2
                                     ELSE 0 END),
        nInNetAmount = sum(CASE WHEN sTypeID IN ('04', '06', '07', '08')
          THEN nNetAmount1
                           ELSE 0 END + CASE WHEN sTypeID IN ('05')
          THEN nNetAmount2
                                        ELSE 0 END),
        nOutQty = sum(CASE WHEN sTypeID IN ('02', '05')
          THEN nQty1
                      ELSE 0 END + CASE WHEN sTypeID IN ('04', '06')
          THEN nQty2
                                   ELSE 0 END),
        nOutAmount = sum(CASE WHEN sTypeID IN ('05')
          THEN nAmount1
                         ELSE 0 END + CASE WHEN sTypeID IN ('02', '04', '06')
          THEN nAmount2
                                      ELSE 0 END),
        nOutNetAmount = sum(CASE WHEN sTypeID IN ('05')
          THEN nNetAmount1
                            ELSE 0 END + CASE WHEN sTypeID IN ('02', '04', '06')
          THEN nNetAmount2
                                         ELSE 0 END),
      0,
      0,
      0,
      min(sTradeModeID)
    FROM #Daily1
    GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, nTaxPct

  IF @@error <> 0
    BEGIN
      RAISERROR ('出问题了', 16, 1)
      RETURN
    END

  /* 看看有新的批次处理了没有，如果没有，那么汇总批次为期末，并计算系统调整，否则计算期末 */
  IF exists(SELECT 1
            FROM rj_DealBatch
            WHERE dDealDate > @rq
                  AND sStoreNO IN (SELECT sStoreNO
                                   FROM #dcs))
    BEGIN
      /* 计算期末 */
      UPDATE #Daily3
      SET nEndQty     = nBeginQty + nInQty - nOutQty, nEndAmount = nBeginAmount + nInAmount - nOutAmount,
        nEndNetAmount = nBeginNetAmount + nInNetAmount - nOutNetAmount

      /* 加加减减出来的期末不含税金额，和含税金额直接计算的，可能有差异，记到系统调整 */
      IF exists(SELECT 1
                FROM #Daily3
                WHERE round(nEndAmount / nTaxPct, 2) <> nEndNetAmount)
        BEGIN
          INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                               nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
            SELECT
              dTradeDate,
              sStoreNO,
              sContractNO,
              nGoodsID,
              sLocatorNO,
              nVendorID,
              '07',
              '损益/系统调整',
              nTaxPct,
              0,
              0,
              0,
              0,
              0,
              round(nEndAmount / nTaxPct, 2) - nEndNetAmount,
              '',
              sTradeModeID,
              NULL,
              NULL
            FROM #Daily3
            WHERE round(nEndAmount / nTaxPct, 2) <> nEndNetAmount
          /* 计算期末不含税金额 */
          UPDATE #Daily3
          SET nEndNetAmount = round(nEndAmount / nTaxPct, 2)
          WHERE round(nEndAmount / nTaxPct, 2) <> nEndNetAmount
        END

      /* 插入期末 */
      INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                           nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
        SELECT
          dTradeDate,
          sStoreNO,
          sContractNO,
          nGoodsID,
          sLocatorNO,
          nVendorID,
          '01',
          '期初/期末',
          nTaxPct,
          0,
          0,
          0,
          nEndQty,
          nEndAmount,
          nEndNetAmount,
          '',
          sTradeModeID,
          NULL,
          NULL
        FROM #Daily3
        WHERE (nEndQty <> 0 OR nEndAmount <> 0)
    END
  ELSE
    BEGIN
      /* 获取批次记录 */
      INSERT INTO #Batch (sStoreNO, nVendorID, nGoodsID, sLocatorNO, nBatchQty, nBatchPrice, nTaxPct, sContractNO, sTradeModeID)
        SELECT
          sStoreNO,
          nVendorID,
          nGoodsID,
          sLocatorNO,
            nBatchQty = nActionQty + nLockedQty - nPendingQty,
          nBatchPrice,
          nBuyTaxPct,
          sContractNO,
          isnull(sTradeModeID, '1')
        FROM tStockBatch
        WHERE nActionQty + nLockedQty - nPendingQty <> 0
              AND sStoreNO IN (SELECT sStoreNO
                               FROM #dcs)
      /* 汇总出期末 */
      INSERT INTO #EndStock (sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, nTaxPct, nEndQty, nEndAmount, nEndNetAmount, sTradeModeID)
        SELECT
          sStoreNO,
          sContractNO,
          nGoodsID,
          sLocatorNO,
          nVendorID,
          nTaxPct,
          sum(nBatchQty),
          sum(round(nBatchQty * nBatchPrice, 2)),
          sum(round(nBatchQty * nBatchPrice / nTaxPct, 2)),
          min(sTradeModeID)
        FROM #Batch
        GROUP BY sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, nTaxPct
      UPDATE #EndStock
      SET nEndNetAmount = round(nEndAmount / nTaxPct, 2)
      WHERE nEndNetAmount <> round(nEndAmount / nTaxPct, 2)
      /* 更新期末 */
      UPDATE #Daily3
      SET nEndQty = b.nEndQty, nEndAmount = b.nEndAmount, nEndNetAmount = b.nEndNetAmount
      FROM #Daily3 AS a, #EndStock AS b
      WHERE a.sStoreNO = b.sStoreNO AND a.sContractNO = b.sContractNO AND a.nGoodsID = b.nGoodsID AND
            a.sLocatorNO = b.sLocatorNO AND a.nTaxPct = b.nTaxPct
      /* 有期末但是总表没有的记录 */
      INSERT INTO #Daily3 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, nTaxPct, nBeginQty, nBeginAmount, nBeginNetAmount,
                           nEndQty, nEndAmount, nEndNetAmount, nInQty, nInAmount, nInNetAmount, nOutQty, nOutAmount, nOutNetAmount,
                           nSysAdjQty, nSysAdjAmount, nSysAdjNetAmount, sTradeModeID)
        SELECT
          @rq,
          sStoreNO,
          sContractNO,
          nGoodsID,
          sLocatorNO,
          nVendorID,
          nTaxPct,
          0,
          0,
          0,
          nEndQty,
          nEndAmount,
          nEndNetAmount,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          sTradeModeID
        FROM #EndStock AS a
        WHERE NOT exists(SELECT 1
                         FROM #Daily3 AS b
                         WHERE a.sStoreNO = b.sStoreNO AND a.sContractNO = b.sContractNO AND a.nGoodsID = b.nGoodsID AND
                               a.nTaxPct = b.nTaxPct AND a.sLocatorNO = b.sLocatorNO)
      /* 计算系统调整 */
      UPDATE #Daily3
      SET nSysAdjQty     = nEndQty - (nBeginQty + nInQty - nOutQty),
        nSysAdjAmount    = nEndAmount - (nBeginAmount + nInAmount - nOutAmount),
        nSysAdjNetAmount = nEndNetAmount - (nBeginNetAmount + nInNetAmount - nOutNetAmount)
      WHERE (nEndQty - (nBeginQty + nInQty - nOutQty) <> 0 OR nEndAmount - (nBeginAmount + nInAmount - nOutAmount) <> 0
             OR nEndNetAmount - (nBeginNetAmount + nInNetAmount - nOutNetAmount) <> 0)
      /* 插入系统调整 */
      INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                           nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
        SELECT
          dTradeDate,
          sStoreNO,
          sContractNO,
          nGoodsID,
          sLocatorNO,
          nVendorID,
          '07',
          '损益/系统调整',
          nTaxPct,
          0,
          0,
          0,
          nSysAdjQty,
          nSysAdjAmount,
          nSysAdjNetAmount,
          '',
          sTradeModeID,
          NULL,
          NULL
        FROM #Daily3
        WHERE nSysAdjQty <> 0 OR nSysAdjAmount <> 0 OR nSysAdjNetAmount <> 0
      /* 插入期末 */
      INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                           nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID)
        SELECT
          dTradeDate,
          sStoreNO,
          sContractNO,
          nGoodsID,
          sLocatorNO,
          nVendorID,
          '01',
          '期初/期末',
          nTaxPct,
          0,
          0,
          0,
          nEndQty,
          nEndAmount,
          nEndNetAmount,
          '',
          sTradeModeID,
          NULL,
          NULL
        FROM #Daily3
        WHERE (nEndQty <> 0 OR nEndAmount <> 0)
    END

  /****************************************************************************
  end of 按照批次处理记录的进销存
  *****************************************************************************/

  UPDATE #Daily1
  SET sCategoryNO = c.sCategoryNO FROM #Daily1 AS a, tGoods AS b, tCategory AS c
  WHERE a.nGoodsID = b.nGoodsID AND b.nCategoryID = c.nCategoryID

  UPDATE #Daily1
  SET sTradeModeID = b.sTradeModeID FROM #Daily1 AS a, tContract AS b
  WHERE a.sContractNO = b.sContractNO AND b.sBusinessTypeID = 'B' AND a.sTradeModeID <> b.sTradeModeID

  UPDATE #Daily1
  SET nSalePrice = b.nSalePrice FROM #Daily1 AS a, tGoods AS b
  WHERE a.nGoodsID = b.nGoodsID AND isnull(a.nSalePrice, 0) <> b.nSalePrice
  UPDATE #Daily1
  SET nSalePrice = 1
  WHERE nSalePrice IS NULL

  DECLARE @err INT
  SELECT @err = 0
  BEGIN TRANSACTION
  INSERT INTO tContractGoodsDaily_DC (dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                                      nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, dLastUpdateTime, nSalePrice, sPRSTypeID)
    SELECT
      dTradeDate,
      sStoreNO,
      sContractNO,
      nGoodsID,
      sLocatorNO,
      nVendorID,
      sTypeID,
      sType,
      nTaxPct,
      sum(nQty1),
      sum(nAmount1),
      sum(nNetAmount1),
      sum(nQty2),
      sum(nAmount2),
      sum(nNetAmount2),
      sCategoryNO,
      sTradeModeID,
      getdate(),
      max(nSalePrice),
      sPRSTypeID
    FROM #Daily1
    GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, sLocatorNO, nVendorID, sTypeID, sType, nTaxPct, sCategoryNO,
      sTradeModeID, sPRSTypeID
  SELECT @err = @err + @@error

  INSERT INTO tContractGoodsDaily (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                                   nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, dLastUpdateTime, nSalePrice, sPRSTypeID)
    SELECT
      dTradeDate,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nVendorID,
      sTypeID,
      sType,
      nTaxPct,
      sum(nQty1),
      sum(nAmount1),
      sum(nNetAmount1),
      sum(nQty2),
      sum(nAmount2),
      sum(nNetAmount2),
      sCategoryNO,
      sTradeModeID,
      getdate(),
      nSalePrice,
      sPRSTypeID
    FROM #Daily1
    WHERE sTypeID NOT IN ('04', '05')
    GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, sCategoryNO, sTradeModeID,
      nSalePrice, sPRSTypeID
  SELECT @err = @err + @@error

  INSERT INTO tContractGoodsDaily (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                                   nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, dLastUpdateTime, nSalePrice, sPRSTypeID)
    SELECT
      dTradeDate,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nVendorID,
      sTypeID,
      sType,
      nTaxPct,
      sum(nQty1),
      sum(nAmount1),
      sum(nNetAmount1),
      sum(-nQty2),
      sum(-nAmount2),
      sum(-nNetAmount2),
      sCategoryNO,
      sTradeModeID,
      getdate(),
      nSalePrice,
      sPRSTypeID
    FROM #Daily1
    WHERE sTypeID IN ('04', '05')
    GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, sCategoryNO, sTradeModeID,
      nSalePrice, sPRSTypeID
  SELECT @err = @err + @@error

  IF @err = 0
    COMMIT TRANSACTION
  ELSE
    BEGIN
      ROLLBACK TRANSACTION
      DROP TABLE #Daily1
      DROP TABLE #Daily2
      DROP TABLE #Daily3
      DROP TABLE #Batch
      DROP TABLE #EndStock
      DROP TABLE #adjd1
      DROP TABLE #ret1
      DROP TABLE #dcs
      RAISERROR ( '插入数据出错', 16, 1)
      RETURN
    END

  DROP TABLE #Daily1
  DROP TABLE #Daily2
  DROP TABLE #Daily3
  DROP TABLE #Batch
  DROP TABLE #EndStock
  DROP TABLE #adjd1
  DROP TABLE #ret1
  DROP TABLE #dcs

END