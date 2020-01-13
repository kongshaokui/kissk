ALTER PROCEDURE [dbo].[rj_ContractDaily](@rq DATETIME) AS
BEGIN
  /*************************************************************
计算合同商品进销存表
版本 4.0
创建时间 2013-01-16
----------------------------------------------------------------------------------
01-期初/期末 02-销售/成本 03-销售调整/成本调整 04-进货/配送 05-退货/退配 06-调入/调出 07-损益/系统调整
21-团购/批发 31-冲差成本/损益成本
71-盘点损益/一般损益  72-批次转换/收货更正  73-客商库调/生鲜分割  74-退货改价/促销扣点
---------------------------------------------------------------------------------
1.1 修改
销售的时候，销项税和批次进项税不一致的，直接用进项税计算
税率调整之后，把历史批次的税率一起调掉
1.2 修改
使用sTypeID in ('02','03')记录(销售记录)的nQty2字段记录小票数
---------------------------------------------------------------------
1.3 修改  2013-04-24
tContractGoodsDaily增加字段nSalePrice, sPRSTypeID
----------------------------------------------------------------------
1.4 修改 2013-04-25
更新合同信息的时候增加判断BusinessTypeID
插入#Daily数据的时候，sTradeModeID原来统一用1，改成取各单据本身的sTradeModeID
---------------------------------------------------------------------
1.5 修改  2013-04-27
增加处理，还存在取不到售价的，直接从tGoods取
--------------------------------------------------------------------
1.6 修改  2013-05-02
增加百货处理，如果是百货分店，sCategoryNO使用柜组号
出现无合同编码的数据，则报错退出
--------------------------------------------------------------------
1.7 修改  2013-07-02
出现销售冲减的时候，插入tPosSaleCost的一正一负记录，
由于现在负批次和tPosSaleCost不是一一对应，所以新增的tPosSaleCost就使用另外独立的小票号
--------------------------------------------------------------------
1.8 修改  2013-07-03
联营销售改成从tPosSaleCost取数据，避免在合同转换的时候和白天处理时联营性质不一致导致缺数据、或数据重复
--------------------------------------------------------------------
1.9 修改  2013-07-30
更新小票数的时候，可能有商品是销售退货，而且数量是小数，小票数就成了个负的小数，到后面插入tGoodsSale取小票数就会报错，
改成前面插入nQty2的时候直接用0
折扣的sPRSTypeID用17
--------------------------------------------------------------------
2.0 修改  2013-08-12
前面改sTypeID=02的nQty2记录小票数的时候，没考虑到下面计算期末的时候，销售数量用的是nQty2，就弄出一堆调整数量了。
修改计算期末的部分，销售数量用nQty1。
--------------------------------------------------------------------
2.1 修改  2013-09-13
发现有些联营商品无法断定是联营(会先插入rj_TmpoBatch，然后批次处理的结果又是联营)，
导致tPosSaleCost的扣点为null的，
加个处理
--------------------------------------------------------------------
2.2 修改  2013-09-20
增加配送红冲的处理，配送红冲是用收货更正的过程处理的，而且插入rj_TmpBatch的时候，
用的是nBatchID=1，以此来和收货更正区分。
在处理进销存之前，先把这部分的rj_DealBatch的s记录改成配送形式，即BsatchTypeID='2', sTmpContractNO='6'
----------------------------------------------------------------
2.3 修改  2013-09-24
增加促销冲差毛利sTypeID='31'.nAmount1的处理
增加POS团购sTypeID='21'.nQty1、后台团购sTypeID='21'.nQty2的处理
增加调整明细
----------------------------------------------------------------
2.4 修改  2013-09-26
负库存产生的调整，重新出库之后的调整，原来漏东西了，补上
--------------------------------------------------------------
2.5 修改  2013-10-10
增加退货改价产生的调整到74, 促销冲差group by 有问题，修正
--------------------------------------------------------------
2.6 修改  2013-11-06
重大BUG啊，2.3版增加调整明细的时候，脚本从处理历史数据的脚本里面拷贝出来，
居然忘了把His表改回正式表，这个调整明细就一直没计算了。
修正
-------------------------------------------------------------
2.7 修改
计算冲减的销售，插入tPosSaleCost的部分，因为代营的记录要在tShoppeVendorSale体现，
而计算tShoppeVendorSale的过程调到合同进销存前面去了，所以这部分从这里移除，放到rj_ShoppeVendorSale
-------------------------------------------------------------
2.8 修改  2014-01-04
日结把批次税率更改的处理，原来有错，修正
--------------------------------------------------------------
2.9 修改  2014-01-21
联营成本从tShoppeVendorSale再更新一次
--------------------------------------------------------------
3.0 修改  2014-02-28
tShoppeVendorSale如果做促销折扣，会有多条记录，先汇总再更新tContractGoodsDaily
--------------------------------------------------------------
3.1 修改  2014-03-19
增加促销扣点调整的购销、代销支持
对应调整，仅在rj_DealBatch有数据，TmpID=0, nBatchID=0，调整的金额，插入毛利调整，同时插入库存调整
--------------------------------------------------------------
3.2 修改  2014-07-02
代营商品，负库存销售，进货后的成本调整，如果进货合同和暂置合同是同一个合同，则不计算成本调整
---------------------------------------------------------------
3.3 修改  2014-08-12
增加对代营0销售的支持
---------------------------------------------------------------
3.4 修改  2014-09-29
上面3.2的修改，导致促销成本调整的也没了，加个处理
---------------------------------------------------------------
3.5 修改  2014-10-06
如果期末是通过计算得出，系统调整不含税金额，正负反了，修正
-------------------------------------------------------------
3.6 修改 2017-01-16
插入团购数据sTypeID='21'的时候，过滤组合商品已拆分数据
raiserror改成函数
return去掉后面的数值，方便调试
-------------------------------------------------------------
3.7 修改 2017-06-27
配送中心业务放到分店库，此过程没处理配送特有的一些业务，所以需要过滤配送中心的数据
配送中心合同进销存使用rj_ContractDaily_DC计算了
-------------------------------------------------------------
3.8 修改 2017-09-02
临时表的主键去掉名称，免得偶尔出现重复……
-------------------------------------------------------------
3.9 修改 2017-10-03
可能是配送进货的问题，联营合同进货了，分店不知道怎么算……（联营的，又没有合同商品关系，扣点就没了）
先加个isnull当0算吧
-------------------------------------------------------------
4.0 修改 2017-10-28
增加双成本
去掉百货相关XX
记录小票数的都用tPosSale了
*************************************************************/
  /* 调整历史批次税率 */
  DECLARE @cdate DATETIME
  SELECT @cdate = convert(VARCHAR, getdate(), 111)
  /* 只有做当天日结的时候才调整批次税率，如果补做就不调了 */
  IF (@cdate = @rq OR (@cdate = dateadd(DD, 1, @rq) AND datepart(HH, getdate()) < 6))
    BEGIN
      UPDATE tStockBatch
      SET nBuyTaxPct = b.nBuyTaxPct FROM tStockBatch AS a, tStoreGoodsVendor AS b
      WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.nVendorID = b.nVendorID
            AND a.nBuyTaxPct <> b.nBuyTaxPct
    END

  DECLARE @DCStore TABLE(sStoreNO VARCHAR(20))
  INSERT INTO @DCStore SELECT sStoreNO
                       FROM tStore
                       WHERE sStoreTypeID = '3'

  CREATE TABLE #Daily1 (
    dTradeDate     DATETIME,
    sStoreNO       VARCHAR(4),
    sContractNO    VARCHAR(20),
    nGoodsID       NUMERIC(8),
    nVendorID      NUMERIC(8),
    sTypeID        VARCHAR(4),
    sType          VARCHAR(20),
    nTaxPct        NUMERIC(8, 5),
    nQty1          NUMERIC(12, 3),
    nAmount1       NUMERIC(12, 2),
    nNetAmount1    NUMERIC(12, 2),
    nQty2          NUMERIC(12, 3),
    nAmount2       NUMERIC(12, 2),
    nNetAmount2    NUMERIC(12, 2),
    sCategoryNO    VARCHAR(8),
    sTradeModeID   VARCHAR(4),
    nSalePrice     NUMERIC(12, 2) NULL,
    sPRSTypeID     VARCHAR(4)     NULL,
    nFinAmount1    NUMERIC(12, 2),
    nFinNetAmount1 NUMERIC(12, 2),
    nFinAmount2    NUMERIC(12, 2),
    nFinNetAmount2 NUMERIC(12, 2)
  )

  CREATE TABLE #Daily3 (
    dTradeDate          DATETIME,
    sStoreNO            VARCHAR(4),
    sContractNO         VARCHAR(20),
    nGoodsID            NUMERIC(8),
    nVendorID           NUMERIC(8),
    nTaxPct             NUMERIC(8, 5),
    nBeginQty           NUMERIC(12, 3),
    nBeginAmount        NUMERIC(12, 2),
    nBeginNetAmount     NUMERIC(12, 2),
    nEndQty             NUMERIC(12, 3),
    nEndAmount          NUMERIC(12, 2),
    nEndNetAmount       NUMERIC(12, 2),
    nInQty              NUMERIC(12, 3),
    nInAmount           NUMERIC(12, 2),
    nInNetAmount        NUMERIC(12, 2),
    nOutQty             NUMERIC(12, 3),
    nOutAmount          NUMERIC(12, 2),
    nOutNetAmount       NUMERIC(12, 2),
    nSysAdjQty          NUMERIC(12, 3),
    nSysAdjAmount       NUMERIC(12, 2),
    nSysAdjNetAmount    NUMERIC(12, 2),
    sTradeModeID        VARCHAR(2),
    nFinBeginAmount     NUMERIC(12, 2) NULL,
    nFinBeginNetAmount  NUMERIC(12, 2) NULL,
    nFinEndAmount       NUMERIC(12, 2) NULL,
    nFinEndNetAmount    NUMERIC(12, 2) NULL,
    nFinInAmount        NUMERIC(12, 2) NULL,
    nFinInNetAmount     NUMERIC(12, 2) NULL,
    nFinOutAmount       NUMERIC(12, 2) NULL,
    nFinOutNetAmount    NUMERIC(12, 2) NULL,
    nFinSysAdjAmount    NUMERIC(12, 2) NULL,
    nFinSysAdjNetAmount NUMERIC(12, 2) NULL,
    PRIMARY KEY (dTradeDate, sStoreNO, sContractNO, nGoodsID, nTaxPct)
  )

  CREATE TABLE #Batch (
    sStoreNO     VARCHAR(4),
    nVendorID    NUMERIC(8),
    nGoodsID     NUMERIC(8),
    nBatchQty    NUMERIC(12, 3),
    nBatchPrice  NUMERIC(12, 4),
    nBatchPrice2 NUMERIC(12, 4) NULL,
    nTaxPct      NUMERIC(8, 5),
    sContractNO  VARCHAR(20),
    sTradeModeID VARCHAR(2)
  )

  CREATE TABLE #EndStock (
    sStoreNO         VARCHAR(4),
    sContractNO      VARCHAR(20),
    nGoodsID         NUMERIC(8),
    nVendorID        NUMERIC(8),
    nTaxPct          NUMERIC(8, 5),
    nEndQty          NUMERIC(12, 3),
    nEndAmount       NUMERIC(12, 2),
    nEndNetAmount    NUMERIC(12, 2),
    nFinEndAmount    NUMERIC(12, 2),
    nFinEndNetAmount NUMERIC(12, 2),
    sTradeModeID     VARCHAR(2)
  )

  CREATE TABLE #ConSale (
    dTradeDate   DATETIME,
    sStoreNO     VARCHAR(4),
    sContractNO  VARCHAR(20),
    nGoodsID     NUMERIC(8),
    nVendorID    NUMERIC(8),
    nTaxPct      NUMERIC(8, 5),
    nSaleQty     NUMERIC(12, 3),
    nSaleAmount  NUMERIC(12, 2),
    nSaleCost    NUMERIC(12, 2),
    sTradeModeID VARCHAR(2),
    nRatio       NUMERIC(6, 4)
  )

  /* 期初 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2,
                       sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID, nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
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
      NULL,
      isnull(nFinAmount2, nAmount2),
      isnull(nFinNetAmount2, nNetAmount2),
      0,
      0
    FROM tContractGoodsDaily
    WHERE dTradeDate = dateadd(DD, -1, @rq) AND sTypeID = '01' AND
          (nQty2 <> 0 OR nAmount2 <> 0 OR isnull(nFinAmount2, nAmount2) <> 0)
          AND sStoreNO NOT IN (SELECT sStoreNO
                               FROM @DCStore)

  /***********************************
2.2 修改  2013-09-20
增加配送红冲的处理，配送红冲是用收货更正的过程处理的，而且插入rj_TmpBatch的时候，
用的是nBatchID=1，以此来和收货更正区分。
在处理进销存之前，先把这部分的rj_DealBatch的记录改成配送形式，即BsatchTypeID='2', sTmpContractNO='6'
***********************************/
  UPDATE rj_DealBatch
  SET sTmpContractNO = '6'
  FROM rj_DealBatch AS a, rj_TmpBatch AS b
  WHERE a.TmpID = b.ID AND a.nType < 2 AND a.sBatchTypeID = '2' AND b.sBatchTypeID = '12'
        AND b.nBatchID = 1 AND a.dDealDate = @rq AND b.dDealDate = @rq
        AND isnull(a.sTmpContractNO, '') <> '6'
        AND a.sStoreNO NOT IN (SELECT sStoreNO
                               FROM @DCStore)

  /* 2.0 修改  2013-09-13
发现有些联营商品无法断定是联营(会先插入rj_TmpoBatch，然后批次处理的结果又是联营)，
导致tPosSaleCost的扣点为null的，
*/
  DELETE FROM rj_DealBatch
  WHERE dDealDate = @rq AND sTradeModeID = '2' AND sStoreNO NOT IN (SELECT sStoreNO
                                                                    FROM @DCStore)
  UPDATE tPosSaleCost
  SET nSaleCost = round(a.nSaleAmount * (1 - b.nRatio * 0.01), 2), nRatio = b.nRatio, dLastUpdateTime = getdate()
  FROM tPosSaleCost AS a, tStoreGoodsVendor AS b, tPosSale AS d
  WHERE d.dUpdate = @rq AND d.dTradeDate = a.dTradeDate AND d.sStoreNO = a.sStoreNO AND d.sPosNO = a.sPosNO AND
        d.nSerID = a.nSerID
        AND a.sTradeModeID IN ('2', '3') AND a.nRatio IS NULL
        AND a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.nVendorID = b.nVendorID AND
        a.sContractNO = b.sContractNO
        AND a.nRatio IS NULL

  /* 汇总销售和成本 */
  /* 版本1.9修改，nQty2用来记录小票数，这里用0插入 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                  AS nVendorID,
      '02',
      '销售/成本',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(-nQty))                                                            AS nSaleQty,
      convert(NUMERIC(12, 2), sum(-nAmount))                                                         AS nSaleAmount,
      convert(NUMERIC(12, 2), sum(round(-nAmount / nTaxPct, 2)))                                     AS nSaleNetAmount,
      convert(NUMERIC(12, 3), 0)                                                                     AS nSheetCount,
      convert(NUMERIC(12, 2), sum(round(CASE WHEN nQty = 0 AND sTradeModeID = '6'
        THEN 1
                                        ELSE -nQty END * nRealBatchPrice, 2)))                       AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(CASE WHEN nQty = 0 AND sTradeModeID = '6'
        THEN 1
                                              ELSE -nQty END * nRealBatchPrice, 2) / nTaxPct, 2)))   AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(CASE WHEN nQty = 0 AND sTradeModeID = '6'
        THEN 1
                                        ELSE -nQty END * isnull(nBatchPrice2, nRealBatchPrice), 2))) AS nFinSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(CASE WHEN nQty = 0 AND sTradeModeID = '6'
        THEN 1
                                              ELSE -nQty END * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                         AS nFinSaleNetCost
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('3', '10') AND nType < 2
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总销售冲减 -- 暂置数据减掉 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sTmpContractNO,
      nGoodsID,
      nTmpVendorID                                                                                               AS nVendorID,
      '03',
      '销售调整/成本调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          nQty))                                                                                                 AS nSaleQty,
      convert(NUMERIC(12, 2), sum(
          nAmount))                                                                                              AS nSaleAmount,
      convert(NUMERIC(12, 2), sum(round(nAmount / nTaxPct,
                                        2)))                                                                     AS nSaleNetAmount,
      convert(NUMERIC(12, 3),
              0)                                                                                                 AS nSheetCount,
      convert(NUMERIC(12, 2), sum(round(nQty * nTmpBatchPrice,
                                        2)))                                                                     AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nTmpBatchPrice, 2) / nTaxPct,
                                        2)))                                                                     AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(nQty * isnull(nTmpBatchPrice2, nTmpBatchPrice),
                                        2)))                                                                     AS nFinSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(nQty * isnull(nTmpBatchPrice2, nTmpBatchPrice), 2) / nTaxPct,
                                        2)))                                                                     AS nFinSaleNetCost
    FROM rj_DealBatch
    WHERE sBatchTypeID = '3' AND nType = 3
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
          AND NOT (sTradeModeID = '6' AND sTmpContractNO = sContractNO AND TmpID <> -1)
    GROUP BY sStoreNO, sTmpContractNO, nGoodsID, nTmpVendorID, nTaxPct
  /* 汇总销售冲减 -- 实际数据加进来 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                             AS nVendorID,
      '03',
      '销售调整/成本调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          -nQty))                                                                                               AS nSaleQty,
      convert(NUMERIC(12, 2), sum(
          -nAmount))                                                                                            AS nSaleAmount,
      convert(NUMERIC(12, 2), sum(round(-nAmount / nTaxPct,
                                        2)))                                                                    AS nSaleNetAmount,
      convert(NUMERIC(12, 3),
              0)                                                                                                AS nSheetCount,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice,
                                        2)))                                                                    AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                    AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                    AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                    AS nSaleNetCost
    FROM rj_DealBatch
    WHERE sBatchTypeID = '3' AND nType = 3
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
          AND NOT (sTradeModeID = '6' AND sTmpContractNO = sContractNO AND TmpID <> -1)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 销售冲减无差别的，删掉 */
  SELECT
    dTradeDate,
    sStoreNO,
    sContractNO,
    nGoodsID,
    nTaxPct,
      a1 = sum(nAmount1),
      a2 = sum(nAmount2),
      a3 = sum(nFinAmount2)
  INTO #SaleNeg
  FROM #Daily1
  WHERE sTypeID = '03'
  GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, nTaxPct
  HAVING sum(nAmount1) = 0 AND sum(nAmount2) = 0 AND sum(nFinAmount2) = 0
  DELETE FROM #Daily1
  FROM #Daily1 AS a, #SaleNeg AS b
  WHERE a.dTradeDate = b.dTradeDate AND a.sStoreNO = b.sStoreNO AND a.sContractNO = b.sContractNO AND
        a.nGoodsID = b.nGoodsID
        AND a.nTaxPct = b.nTaxPct AND a.sTypeID = '03'
  /* 版本 3.1 购销代销的促销毛利调整，插入调整 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID, nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                       AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      0,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice, 2)))                     AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSaleNetCost,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID = '3' AND nType = 3 AND TmpID = 0 AND nBatchID = 0 AND nQty = -1 AND nAmount = 0 AND
          nTmpBatchPrice = 0
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct

  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1, nQty2,
                       nAmount2, nNetAmount2,
                       sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID, nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                       AS nVendorID,
      '74',
      '退货改价/促销扣点',
      nTaxPct,
      0,
      0,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice, 2)))                     AS nSaleCost,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSaleNetCost,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID = '3' AND nType = 3 AND TmpID = 0 AND nBatchID = 0 AND nQty = -1 AND nAmount = 0 AND
          nTmpBatchPrice = 0
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 防止有销项税和进项税不一致的  都用进项税来计算
update #Daily1 set nNetAmount1=round(a.nAmount1/b.nSaleTaxPct,2)
  from #Daily1 as a, tStoreGoods as b
  where a.sTypeID in ('02','03') and a.sStoreNO=b.sStoreNO and a.nGoodsID=b.nGoodsID
  and nNetAmount1<>round(a.nAmount1/b.nSaleTaxPct,2)
*/

  /* 汇总进货 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                            AS nVendorID,
      '04',
      '进货/配送',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          nQty))                                                                                               AS nAcptQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice,
                                        2)))                                                                   AS nAcptAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                   AS nAcptNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      convert(NUMERIC(12, 2), sum(round(nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                   AS nFinAcptAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                   AS nFinAcptNetAmount,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID = '2' AND nType < 2 AND isnull(sTmpContractNO, '') <> '6'
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总配送 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                            AS nVendorID,
      '04',
      '进货/配送',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(
          nQty))                                                                                               AS nAcptQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice,
                                        2)))                                                                   AS nAcptAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                   AS nAcptNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                   AS nFinAcptAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                   AS nFinAcptNetAmount
    FROM rj_DealBatch
    WHERE sBatchTypeID = '2' AND nType < 2 AND isnull(sTmpContractNO, '') = '6'
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总退货*/
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                             AS nVendorID,
      '05',
      '退货/退配',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          -nQty))                                                                                               AS nReturnQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice,
                                        2)))                                                                    AS nReturnAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                    AS nReturnNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      convert(NUMERIC(12, 2), sum(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                    AS nFinReturnAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                    AS nFinReturnNetAmount,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID = '6' AND nType < 2
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总退配*/
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1, nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                             AS nVendorID,
      '05',
      '退货/退配',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(
          -nQty))                                                                                               AS nDCOutQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice,
                                        2)))                                                                    AS nDCOutAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                    AS nDCOutNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                    AS nFinDCOutAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                    AS nFinDCOutNetAmount
    FROM rj_DealBatch
    WHERE sBatchTypeID = '7' AND nType < 2 AND isnull(sTmpContractNO, '') = '2'
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总调入 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                            AS nVendorID,
      '06',
      '调入/调出',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          nQty))                                                                                               AS nReturnQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice,
                                        2)))                                                                   AS nTransInAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                   AS nTransInNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      convert(NUMERIC(12, 2), sum(round(nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                   AS nFinTransInAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                   AS nFinTransInNetAmount,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID = '4' AND nType < 2
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总调出*/
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1, nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                             AS nVendorID,
      '06',
      '调入/调出',
      nTaxPct,
      0,
      0,
      0,
      convert(NUMERIC(12, 3), sum(
          -nQty))                                                                                               AS nTransOutQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice,
                                        2)))                                                                    AS nTransOutAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                    AS nTransOutNetAmount,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      0,
      0,
      convert(NUMERIC(12, 2), sum(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                    AS nFinTransOutAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                    AS nFinTransOutNetAmount
    FROM rj_DealBatch
    WHERE sBatchTypeID = '7' AND nType < 2 AND isnull(sTmpContractNO, '') <> '2'
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
  /* 汇总调整*/
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                            AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          nQty))                                                                                               AS nAdjQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice,
                                        2)))                                                                   AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                   AS nAdjNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      convert(NUMERIC(12, 2), sum(round(nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                   AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                   AS nAdjNetAmount,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('5', '8') AND nType < 2
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct

  /* 调整冲减-暂置调整减掉 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sTmpContractNO,
      nGoodsID,
      nTmpVendorID                                                                                                AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          -nQty))                                                                                                 AS nAdjQty,
      convert(NUMERIC(12, 2), sum(round(-nQty * nTmpBatchPrice,
                                        2)))                                                                      AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * nTmpBatchPrice, 2) / nTaxPct,
                                        2)))                                                                      AS nAdjNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      convert(NUMERIC(12, 2), sum(round(-nQty * isnull(nTmpBatchPrice2, nTmpBatchPrice),
                                        2)))                                                                      AS nFinAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(-nQty * isnull(nTmpBatchPrice2, nTmpBatchPrice), 2) / nTaxPct,
                                        2)))                                                                      AS nFinAdjNetAmount,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('5', '8') AND nType = 3
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sTmpContractNO, nGoodsID, nTmpVendorID, nTaxPct
  /* 调整冲减-实际调整加进来 */
  INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                       nAmount1, nNetAmount1,
                       nQty2, nAmount2,
                       nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                       nFinAmount1, nFinNetAmount1,
                       nFinAmount2, nFinNetAmount2)
    SELECT
      @rq,
      sStoreNO,
      sContractNO,
      nGoodsID,
      nRealVendorID                                                                                            AS nVendorID,
      '07',
      '损益/系统调整',
      nTaxPct,
      convert(NUMERIC(12, 3), sum(
          nQty))                                                                                               AS nAdjQty,
      convert(NUMERIC(12, 2), sum(round(nQty * nRealBatchPrice,
                                        2)))                                                                   AS nAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * nRealBatchPrice, 2) / nTaxPct,
                                        2)))                                                                   AS nAdjNetAmount,
      0,
      0,
      0,
      '',
      min(isnull(sTradeModeID, '1')),
      NULL,
      NULL,
      convert(NUMERIC(12, 2), sum(round(nQty * isnull(nBatchPrice2, nRealBatchPrice),
                                        2)))                                                                   AS nFinAdjAmount,
      convert(NUMERIC(12, 2), sum(round(round(nQty * isnull(nBatchPrice2, nRealBatchPrice), 2) / nTaxPct,
                                        2)))                                                                   AS nFinAdjNetAmount,
      0,
      0
    FROM rj_DealBatch
    WHERE sBatchTypeID IN ('5', '8') AND nType = 3
          AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                   FROM @DCStore)
    GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct

  /* 联营销售 -- 2013-07-03 修改 从tPosSaleCost取数据 */
  INSERT INTO #ConSale (dTradeDate, sStoreNO, sContractNO, nVendorID, nGoodsID, nTaxPct,
                        nSaleQty, nSaleAmount, nSaleCost, sTradeModeID, nRatio)
    SELECT
      @rq,
      b.sStoreNO,
      sContractNO,
      nVendorID,
      nGoodsID,
      nTaxPct,
      sum(nSaleQty),
      sum(b.nSaleAmount),
      sum(nSaleCost),
      sTradeModeID,
      isnull(max(nRatio), 0)
    FROM tPosSale AS a WITH ( INDEX = Ind_Update), tPosSaleCost AS b WITH (INDEX = PK_TPOSSALECOST)
WHERE a.dUpdate=@rq AND a.dTradeDate=b.dTradeDate AND a.sStoreNO=b.sStoreNO AND a.sPosNO=b.sPosNO AND a.nSerID=b.nSerID
AND b.sTradeModeID IN ('2', '3') AND a.sStoreNO NOT IN ( SELECT sStoreNO FROM @DCStore)
GROUP BY b.sStoreNO, sContractNO, nVendorID, nGoodsID, nTaxPct, sTradeModeID
IF @@error <> 0
  RETURN

IF exists(SELECT 1
          FROM #ConSale) AND NOT exists(SELECT 1
                                        FROM tShoppeVendorSale
                                        WHERE dTradeDate = @rq AND sTradeModeID IN ('2', '3'))
  BEGIN
    RAISERROR ('tShoppeVendorSale 计算有问题!', 16, 1)
    RETURN
  END

/* 版本1.2 根据tShoppeVendorSale更新一下 */
SELECT
  sStoreNO,
  nVendorID,
  nGoodsID,
    cc = count(*)
INTO #Con01
FROM #ConSale
GROUP BY sStoreNO, nVendorID, nGoodsID
HAVING count(*) = 1
/* 版本3.0 tShoppeVendorSale如果做促销折扣，会有多条记录，先汇总再更新tContractGoodsDaily */
SELECT
  dTradeDate,
  sStoreNO,
  sContractNO,
  nVendorID,
  nGoodsID,
  nBuyTaxPct,
  sTradeModeID,
    nSaleQty = sum(nSaleQty),
    nSaleAmount = sum(nSaleAmount),
    nSaleCost = sum(nSaleCost)
INTO #Con02
FROM tShoppeVendorSale
WHERE dTradeDate = @rq
GROUP BY dTradeDate, sStoreNO, sContractNO, nVendorID, nGoodsID, nBuyTaxPct, sTradeModeID

UPDATE #ConSale
SET nSaleCost = b.nSaleCost FROM #ConSale AS a, #Con02 AS b, #Con01 AS c
WHERE a.dTradeDate = b.dTradeDate AND a.sStoreNO = b.sStoreNO AND a.nVendorID = b.nVendorID AND a.nGoodsID = b.nGoodsID
      AND a.sContractNO = b.sContractNO AND a.nSaleCost <> b.nSaleCost
      AND a.sStoreNO = c.sStoreNO AND a.nVendorID = c.nVendorID AND a.nGoodsID = c.nGoodsID

DROP TABLE #Con01
DROP TABLE #Con02
/* 1.2 end ****************************************/

INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                     nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                     nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
  SELECT
    @rq,
    sStoreNO,
    sContractNO,
    nGoodsID,
    nVendorID,
    '02',
    '销售/成本',
    nTaxPct,
    nSaleQty,
    nSaleAmount,
    round(nSaleAmount / nTaxPct, 2),
    0,
    nSaleCost,
    round(nSaleCost / nTaxPct, 2),
    '',
    sTradeModeID,
    NULL,
    NULL,
    0,
    0,
    0,
    0
  FROM #ConSale
INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                     nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                     nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
  SELECT
    @rq,
    sStoreNO,
    sContractNO,
    nGoodsID,
    nVendorID,
    '04',
    '进货/配送',
    nTaxPct,
    nSaleQty,
    nSaleCost,
    round(nSaleCost / nTaxPct, 2),
    0,
    0,
    0,
    '',
    sTradeModeID,
    NULL,
    NULL,
    0,
    0,
    0,
    0
  FROM #ConSale

/***********************************************************************************/
/* 汇总弄到进销存临时表，准备计算系统调整，或者计算期末 */
/* 2.0 修改  2013-08-12 销售数量用nQty1 */
INSERT INTO #Daily3 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, nTaxPct, nBeginQty, nBeginAmount, nBeginNetAmount,
                     nEndQty, nEndAmount, nEndNetAmount, nInQty,
                     nInAmount,
                     nInNetAmount,
                     nOutQty,
                     nOutAmount,
                     nOutNetAmount,
                     nSysAdjQty, nSysAdjAmount, nSysAdjNetAmount, sTradeModeID,
                     nFinBeginAmount, nFinBeginNetAmount,
                     nFinEndAmount, nFinEndNetAmount,
                     nFinInAmount,
                     nFinInNetAmount,
                     nFinOutAmount,
                     nFinOutNetAmount)
  SELECT
    dTradeDate,
    sStoreNO,
    sContractNO,
    nGoodsID,
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
    sum(CASE WHEN sTypeID IN ('04', '06', '07')
      THEN nQty1
        ELSE 0 END + CASE WHEN sTypeID IN ('04')
      THEN nQty2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('04', '06', '07')
      THEN nAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('04')
      THEN nAmount2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('04', '06', '07')
      THEN nNetAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('04')
      THEN nNetAmount2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('02', '03', '05')
      THEN nQty1
        ELSE 0 END + CASE WHEN sTypeID IN ('05', '06')
      THEN nQty2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('05')
      THEN nAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('02', '03', '05', '06')
      THEN nAmount2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('05')
      THEN nNetAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('02', '03', '05', '06')
      THEN nNetAmount2
                     ELSE 0 END),
    0,
    0,
    0,
    min(sTradeModeID),
    sum(CASE WHEN sTypeID = '01'
      THEN nFinAmount1
        ELSE 0 END),
    sum(CASE WHEN sTypeID = '01'
      THEN nFinNetAmount1
        ELSE 0 END),
    0,
    0,
    sum(CASE WHEN sTypeID IN ('04', '06', '07')
      THEN nFinAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('04')
      THEN nFinAmount2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('04', '06', '07')
      THEN nFinNetAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('04')
      THEN nFinNetAmount2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('05')
      THEN nFinAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('02', '03', '05', '06')
      THEN nFinAmount2
                     ELSE 0 END),
    sum(CASE WHEN sTypeID IN ('05')
      THEN nFinNetAmount1
        ELSE 0 END + CASE WHEN sTypeID IN ('02', '03', '05', '06')
      THEN nFinNetAmount2
                     ELSE 0 END)
  FROM #Daily1
  GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, nTaxPct
/* 看看有新的批次处理了没有，如果没有，那么汇总批次为期末，并计算系统调整，否则计算期末 */
IF exists(SELECT 1
          FROM rj_DealBatch
          WHERE dDealDate > @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                                     FROM @DCStore))
  BEGIN
    /* 计算期末 */
    UPDATE #Daily3
    SET nEndQty        = nBeginQty + nInQty - nOutQty, nEndAmount = nBeginAmount + nInAmount - nOutAmount,
      nEndNetAmount    = nBeginNetAmount + nInNetAmount - nOutNetAmount,
      nFinEndAmount    = nFinBeginAmount + nFinInAmount - nFinOutAmount,
      nFinEndNetAmount = nFinBeginNetAmount + nFinInNetAmount - nFinOutNetAmount
    /* 加加减减出来的期末不含税金额，和含税金额直接计算的，可能有差异，记到系统调整 */
    INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                         nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                         nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
      SELECT
        dTradeDate,
        sStoreNO,
        sContractNO,
        nGoodsID,
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
        NULL,
        0,
        0,
        0,
        round(nFinEndAmount / nTaxPct, 2) - nFinEndNetAmount
      FROM #Daily3
      WHERE (round(nEndAmount / nTaxPct, 2) <> nEndNetAmount OR round(nFinEndAmount / nTaxPct, 2) <> nFinEndNetAmount)
    /* 计算期末不含税金额 */
    UPDATE #Daily3
    SET nEndNetAmount = round(nEndAmount / nTaxPct, 2)
    WHERE round(nEndAmount / nTaxPct, 2) <> nEndNetAmount
    UPDATE #Daily3
    SET nFinEndNetAmount = round(nFinEndAmount / nTaxPct, 2)
    WHERE round(nFinEndAmount / nTaxPct, 2) <> nFinEndNetAmount
    /* 插入期末 */
    INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                         nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                         nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
      SELECT
        dTradeDate,
        sStoreNO,
        sContractNO,
        nGoodsID,
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
        NULL,
        0,
        0,
        nFinEndAmount,
        nFinEndNetAmount
      FROM #Daily3
      WHERE (nEndQty <> 0 OR nEndAmount <> 0 OR nFinEndAmount <> 0)
  END
ELSE
  BEGIN
    /* 获取批次记录 */
    INSERT INTO #Batch (sStoreNO, nVendorID, nGoodsID, nBatchQty, nBatchPrice, nBatchPrice2, nTaxPct, sContractNO, sTradeModeID)
      SELECT
        sStoreNO,
        nVendorID,
        nGoodsID,
          nBatchQty = nActionQty + nLockedQty - nPendingQty,
        nBatchPrice,
        nBatchPrice2,
        nBuyTaxPct,
        sContractNO,
        isnull(sTradeModeID, '1')
      FROM tStockBatch
      WHERE nActionQty + nLockedQty - nPendingQty <> 0 AND sStoreNO NOT IN (SELECT sStoreNO
                                                                            FROM @DCStore)
    /* 没有合同号的 */
    UPDATE #Batch
    SET sContractNO = b.sContractNO FROM #Batch AS a, tStoreGoodsVendor AS b
    WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.nVendorID = b.nVendorID AND
          isnull(a.sContractNO, '') = ''
    /* 汇总出期末 */
    INSERT INTO #EndStock (sStoreNO, sContractNO, nGoodsID, nVendorID, nTaxPct, nEndQty, nEndAmount, nEndNetAmount,
                           nFinEndAmount, nFinEndNetAmount, sTradeModeID)
      SELECT
        sStoreNO,
        sContractNO,
        nGoodsID,
        nVendorID,
        nTaxPct,
        sum(nBatchQty),
        sum(round(nBatchQty * nBatchPrice, 2)),
        sum(round(nBatchQty * nBatchPrice / nTaxPct, 2)),
        sum(round(nBatchQty * isnull(nBatchPrice2, nBatchPrice), 2)),
        sum(round(nBatchQty * isnull(nBatchPrice2, nBatchPrice) / nTaxPct, 2)),
        min(sTradeModeID)
      FROM #Batch
      GROUP BY sStoreNO, sContractNO, nGoodsID, nVendorID, nTaxPct
    UPDATE #EndStock
    SET nEndNetAmount = round(nEndAmount / nTaxPct, 2)
    WHERE nEndNetAmount <> round(nEndAmount / nTaxPct, 2)
    UPDATE #EndStock
    SET nFinEndNetAmount = round(nFinEndAmount / nTaxPct, 2)
    WHERE nFinEndNetAmount <> round(nFinEndAmount / nTaxPct, 2)
    /* 更新期末 */
    UPDATE #Daily3
    SET nEndQty     = b.nEndQty, nEndAmount = b.nEndAmount, nEndNetAmount = b.nEndNetAmount,
      nFinEndAmount = b.nFinEndAmount, nFinEndNetAmount = b.nFinEndNetAmount
    FROM #Daily3 AS a, #EndStock AS b
    WHERE
      a.sStoreNO = b.sStoreNO AND a.sContractNO = b.sContractNO AND a.nGoodsID = b.nGoodsID AND a.nTaxPct = b.nTaxPct
    /* 有期末但是总表没有的记录 */
    INSERT INTO #Daily3 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, nTaxPct, nBeginQty, nBeginAmount, nBeginNetAmount,
                         nEndQty, nEndAmount, nEndNetAmount, nInQty, nInAmount, nInNetAmount, nOutQty, nOutAmount, nOutNetAmount,
                         nSysAdjQty, nSysAdjAmount, nSysAdjNetAmount, sTradeModeID,
                         nFinBeginAmount, nFinBeginNetAmount, nFinEndAmount, nFinEndNetAmount, nFinInAmount, nFinInNetAmount,
                         nFinOutAmount, nFinOutNetAmount, nFinSysAdjAmount, nFinSysAdjNetAmount)
      SELECT
        @rq,
        sStoreNO,
        sContractNO,
        nGoodsID,
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
        sTradeModeID,
        0,
        0,
        nFinEndAmount,
        nFinEndNetAmount,
        0,
        0,
        0,
        0,
        0,
        0
      FROM #EndStock AS a
      WHERE NOT exists(SELECT 1
                       FROM #Daily3 AS b
                       WHERE a.sStoreNO = b.sStoreNO AND a.sContractNO = b.sContractNO AND a.nGoodsID = b.nGoodsID AND
                             a.nTaxPct = b.nTaxPct)
    /* 计算系统调整 */
    UPDATE #Daily3
    SET nSysAdjQty        = nEndQty - (nBeginQty + nInQty - nOutQty),
      nSysAdjAmount       = nEndAmount - (nBeginAmount + nInAmount - nOutAmount),
      nSysAdjNetAmount    = nEndNetAmount - (nBeginNetAmount + nInNetAmount - nOutNetAmount),
      nFinSysAdjAmount    = nFinEndAmount - (nFinBeginAmount + nFinInAmount - nFinOutAmount),
      nFinSysAdjNetAmount = nFinEndNetAmount - (nFinBeginNetAmount + nFinInNetAmount - nFinOutNetAmount)
    WHERE (nEndQty - (nBeginQty + nInQty - nOutQty) <> 0 OR nEndAmount - (nBeginAmount + nInAmount - nOutAmount) <> 0
           OR nEndNetAmount - (nBeginNetAmount + nInNetAmount - nOutNetAmount) <> 0
           OR nFinEndAmount - (nFinBeginAmount + nFinInAmount - nFinOutAmount) <> 0
           OR nFinEndNetAmount - (nFinBeginNetAmount + nFinInNetAmount - nFinOutNetAmount) <> 0)
    /* 插入系统调整 */
    INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                         nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                         nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
      SELECT
        dTradeDate,
        sStoreNO,
        sContractNO,
        nGoodsID,
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
        NULL,
        0,
        0,
        nFinSysAdjAmount,
        nFinSysAdjNetAmount
      FROM #Daily3
      WHERE nSysAdjQty <> 0 OR nSysAdjAmount <> 0 OR nSysAdjNetAmount <> 0 OR nFinSysAdjAmount <> 0 OR
            nFinSysAdjNetAmount <> 0
    /* 插入期末 */
    INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                         nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                         nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
      SELECT
        dTradeDate,
        sStoreNO,
        sContractNO,
        nGoodsID,
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
        NULL,
        0,
        0,
        nFinEndAmount,
        nFinEndNetAmount
      FROM #Daily3
      WHERE (nEndQty <> 0 OR nEndAmount <> 0 OR nFinEndAmount <> 0)
  END

/* 版本2.3 增加，团购/批发 */
INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct,
                     nQty1, nAmount1,
                     nNetAmount1,
                     nQty2, nAmount2,
                     nNetAmount2,
                     sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID, nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
  SELECT
    @rq,
    b.sStoreNO,
    b.sContractNO,
    b.nGoodsID,
    b.nVendorID,
    '21',
    '团购/批发',
    b.nTaxPct,
    CASE WHEN b.sPosNO <> '999'
      THEN nSaleQty
    ELSE 0 END,
    CASE WHEN b.sPosNO <> '999'
      THEN b.nSaleAmount
    ELSE 0 END,
    CASE WHEN b.sPosNO <> '999'
      THEN round(b.nSaleAmount / b.nTaxPct, 2)
    ELSE 0 END,
    CASE WHEN b.sPosNO = '999'
      THEN nSaleQty
    ELSE 0 END,
    CASE WHEN b.sPosNO = '999'
      THEN b.nSaleAmount
    ELSE 0 END,
    CASE WHEN b.sPosNO = '999'
      THEN round(b.nSaleAmount / b.nTaxPct, 2)
    ELSE 0 END,
    '',
    b.sTradeModeID,
    b.nSalePrice,
    NULL,
    0,
    0,
    0,
    0
  FROM tPosSale AS a, tPosSaleCost AS b
  WHERE a.sStoreNO = b.sStoreNO AND a.dTradeDate = b.dTradeDate AND a.sPosNO = b.sPosNO AND a.nSerID = b.nSerID
        AND a.sStoreNO NOT IN (SELECT sStoreNO
                               FROM @DCStore)
        AND a.dUpdate = @rq AND a.nTag & 2 = 2 AND a.nTradeType IN (0, 2) AND a.nTradeStatus = 2
        AND ISNULL(b.sMemo, '') <> '组合商品已拆分'

/* 版本2.3 增加，促销冲差 */
SELECT
  a.sPaperNO,
  a.sStoreNO,
  a.nGoodsID,
    nSaleQty = sum(nSaleQty),
    nAmount = sum(nFeeAmount),
  a.nVendorID,
  a.sContractNO,
    nTaxPct = convert(NUMERIC(8, 5), 1 + b.nSaleTaxRate * 0.01),
    sTradeModeID = convert(VARCHAR(2), '1'),
    nSalePrice = b.nSalePrice
INTO #sd
FROM tSaleDisStoreGoods AS a, tGoods AS b
WHERE a.dLastUpdateTime >= dateadd(DD, -10, @rq) AND a.nTag & 16 = 0 AND a.nGoodsID = b.nGoodsID
GROUP BY a.sPaperNO, a.sStoreNO, a.nGoodsID, a.nVendorID, a.sContractNO,
  convert(NUMERIC(8, 5), 1 + b.nSaleTaxRate * 0.01),
  b.nSalePrice

UPDATE #sd
SET sTradeModeID = b.sTradeModeID FROM #sd AS a, tContract AS b
WHERE a.sContractNO = b.sContractNO AND a.sTradeModeID <> b.sTradeModeID
UPDATE #sd
SET nSalePrice = b.nSalePrice FROM #sd AS a, tStoreGoods AS b
WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.nSalePrice <> b.nSalePrice

INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct,
                     nQty1, nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2,
                     sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID, nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
  SELECT
    @rq,
    sStoreNO,
    sContractNO,
    nGoodsID,
    nVendorID,
    '31',
    '促销冲差/损益成本',
    nTaxPct,
    -nSaleQty,
    -nAmount,
    -round(nAmount / nTaxPct, 2),
    0,
    0,
    0,
    '',
    sTradeModeID,
    nSalePrice,
    NULL,
    0,
    0,
    0,
    0
  FROM #sd

/*************************************************/
/* 版本2.3 增加，调整明细 */
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
  a.sTradeModeID
INTO #adj1
FROM rj_DealBatch AS a, rj_TmpBatch AS b
WHERE a.dDealDate = @rq AND a.TmpID = b.ID
      AND a.sBatchTypeID IN ('5', '8') AND a.sStoreNO NOT IN (SELECT sStoreNO
                                                              FROM @DCStore)
      AND a.nType < 2

/* 先取得生鲜分割的 */
UPDATE #adj1
SET sAdjType = '732'
WHERE sTmpContractNO IN ('母商品负', '子商品正')

/* 客商库调 */
UPDATE #adj1
SET sAdjType = '731'
WHERE sAdjType = '' AND sTmpBatchTypeID IN ('5', '8') AND sOrgContractNO IS NOT NULL

/* 批次转换 */
UPDATE #adj1
SET sAdjType = '721'
WHERE sAdjType = '' AND sTmpBatchTypeID = '15'

/* 收货更正 */
UPDATE #adj1
SET sAdjType = '722'
WHERE sAdjType = '' AND sTmpBatchTypeID = '12'

/* 退货改价 */
UPDATE #adj1
SET sAdjType = '741'
WHERE sAdjType = '' AND sTmpContractNO = '退货差价'
/* 盘点损益/一般损益 */
UPDATE #adj1
SET sAdjType = CASE WHEN b.sAdjustTypeId IN ('1', '2')
  THEN '711'
               WHEN b.sAdjustTypeId IN ('3', '6')
                 THEN '712' END
FROM #adj1 AS a, tStockAdj AS b
WHERE a.sAdjType = '' AND a.sTmpBatchTypeID IN ('5', '8') AND a.sStoreNO = b.sStoreNO AND a.sPaperNO = b.sPaperNO
      AND b.sAdjustTypeId IN ('1', '2', '3', '6')

DELETE FROM #adj1
WHERE sAdjType = ''

INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID,
                     sTypeID, sType, nTaxPct, nQty1,
                     nAmount1, nNetAmount1,
                     nQty2, nAmount2,
                     nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID, nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
  SELECT
    @rq,
    sStoreNO,
    sContractNO,
    nGoodsID,
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
    NULL,
    0,
    0,
    0,
    0
  FROM #adj1
  WHERE sAdjType <> ''
  GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct, substring(sAdjType, 1, 2),
    CASE substring(sAdjType, 1, 2)
    WHEN '71'
      THEN '盘点损益/一般损益'
    WHEN '72'
      THEN '批次转换/收货更正'
    WHEN '73'
      THEN '客商库调/生鲜分割'
    WHEN '74'
      THEN '退货改价/促销扣点' END
/* 版本 3.1 购销代销的促销毛利调整，插入调整 */
INSERT INTO #Daily1 (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                     nAmount1, nNetAmount1,
                     nQty2, nAmount2,
                     nNetAmount2, sCategoryNO, sTradeModeID, nSalePrice, sPRSTypeID,
                     nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
  SELECT
    @rq,
    sStoreNO,
    sContractNO,
    nGoodsID,
    nRealVendorID                                                                       AS nVendorID,
    '74',
    '退货改价/促销扣点',
    nTaxPct,
    0,
    0,
    0,
    0,
    convert(NUMERIC(12, 2), sum(round(-nQty * nRealBatchPrice, 2)))                     AS nSaleCost,
    convert(NUMERIC(12, 2), sum(round(round(-nQty * nRealBatchPrice, 2) / nTaxPct, 2))) AS nSaleNetCost,
    '',
    min(isnull(sTradeModeID, '1')),
    NULL,
    NULL,
    0,
    0,
    0,
    0
  FROM rj_DealBatch
  WHERE
    sBatchTypeID = '3' AND nType = 3 AND TmpID = 0 AND nBatchID = 0 AND nQty = 1 AND nAmount = 0 AND nTmpBatchPrice = 0
    AND dDealDate = @rq AND sStoreNO NOT IN (SELECT sStoreNO
                                             FROM @DCStore)
  GROUP BY sStoreNO, sContractNO, nGoodsID, nRealVendorID, nTaxPct
/*************************************************/

/* 用sTypeID='02'(销售)的nQty2记录小票数 */
SELECT
  b.sStoreNO,
  b.nGoodsID,
    nSheetCount = count(DISTINCT b.sPosNO + convert(VARCHAR, 10000 + b.nSerID))
INTO #sheetc
FROM tPosSale AS a, tPosSaleDtl AS b
WHERE a.sStoreNO = b.sStoreNO AND a.dTradeDate = b.dTradeDate AND a.sPosNO = b.sPosNO AND a.nSerID = b.nSerID
      AND a.dUpdate = @rq AND a.nTradeType = 0 AND a.nTradeStatus = 2
GROUP BY b.sStoreNO, b.nGoodsID
UPDATE #Daily1
SET nQty2 = b.nSheetCount
FROM #Daily1 AS a, #sheetc AS b
WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID
      AND a.sTypeID IN ('02', '03')
DROP TABLE #sheetc

IF exists(SELECT 1
          FROM #Daily1
          WHERE isnull(sContractNO, '') = '')
  BEGIN
    RAISERROR ('存在无合同的数据，请检查！！', 16, 1)
    RETURN
  END

UPDATE #Daily1
SET sCategoryNO = c.sCategoryNO FROM #Daily1 AS a, tGoods AS b, tCategory AS c
WHERE a.nGoodsID = b.nGoodsID AND b.nCategoryID = c.nCategoryID

/* 从合同更新交易方式 */
UPDATE #Daily1
SET sTradeModeID = b.sTradeModeID FROM #Daily1 AS a, tContract AS b
WHERE a.sContractNO = b.sContractNO AND b.sBusinessTypeID = 'B' AND a.sTradeModeID <> b.sTradeModeID

/* 更新售价、促销标记 */
UPDATE #Daily1
SET sPRSTypeID = b.sPRSTypeID, nSalePrice = b.nSalePrice FROM #Daily1 AS a, rj_SalePrice_op AS b
WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID

/*************************************/
/* 折扣信息 -- 一般折扣 */
SELECT
  c.sStoreNO,
    sPaperNO = a.sPaperNO,
  a.sDisTypeID,
  a.dBeginDate,
  a.dEndDate,
  a.dConfirmDate,
  b.nGoodsID,
    nSalePrice = CASE WHEN a.sDisTypeID = '1'
      THEN b.nPrice
                 ELSE convert(NUMERIC(12, 2), round(b.nAmount / b.nQty, 2)) END
INTO #dis1
FROM tDiscount AS a, tDisGoods AS b, tDisStore AS c
WHERE a.sPaperNO = b.sPaperNO AND a.sPaperNO = c.sPaperNO
      AND a.sDisTypeID IN ('1', '2') AND a.dBeginDate <= @rq AND a.dEndDate >= @rq
      AND (a.nTag & 3 = 2 OR (a.nTag & 1 = 1 AND a.dLastUpdateTime >= @rq AND a.dLastUpdateTime < dateadd(DD, 1, @rq)))
/* 折扣信息 -- 混搭折扣 */
INSERT INTO #dis1 (sStoreNO, sPaperNO, sDisTypeID, dBeginDate, dEndDate, dConfirmDate, nGoodsID, nSalePrice)
  SELECT
    c.sStoreNO,
      sPaperNO = a.sPaperNO + 'D',
    a.sDisTypeID,
    a.dBeginDate,
    a.dEndDate,
    a.dConfirmDate,
    b.nGoodsID,
      nSalePrice = b.nPrice
  FROM tDiscount AS a, tDisGoodsGr AS b, tDisStore AS c
  WHERE a.sPaperNO = b.sPaperNO AND a.sPaperNO = c.sPaperNO
        AND a.sDisTypeID = '3' AND a.dBeginDate <= @rq AND a.dEndDate >= @rq
        AND
        (a.nTag & 3 = 2 OR (a.nTag & 1 = 1 AND a.dLastUpdateTime >= @rq AND a.dLastUpdateTime < dateadd(DD, 1, @rq)))
/* 折扣最大审核日 */
SELECT
  sStoreNO,
  nGoodsID,
    dConfirmDate = max(dConfirmDate)
INTO #dis2
FROM #dis1
GROUP BY sStoreNO, nGoodsID
DELETE FROM #dis1 FROM #dis1 AS a, #dis2 AS b
WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.dConfirmDate <> b.dConfirmDate
/* 唯一的折扣商品信息 */
SELECT
  sStoreNO,
  nGoodsID,
    sPromoNO = convert(VARCHAR(20), NULL),
    sPaperNO = max(sPaperNO),
    sDisTypeID = min(sDisTypeID),
    dSaleBeginDate = min(dBeginDate),
    dSaleEndDate = max(dEndDate),
    dConfirmDate = max(dConfirmDate),
    nSalePrice = min(nSalePrice)
INTO #dis3
FROM #dis1
GROUP BY sStoreNO, nGoodsID
UPDATE #Daily1
SET sPRSTypeID = '17' FROM #Daily1 AS a, #dis3 AS b
WHERE a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.sPRSTypeID IS NULL

/*************************************/
/* 版本1.5 增加处理，还存在取不到售价的，直接从tGoods取 */
UPDATE #Daily1
SET nSalePrice = b.nSalePrice FROM #Daily1 AS a, tGoods AS b
WHERE a.nGoodsID = b.nGoodsID AND a.nSalePrice IS NULL
UPDATE #Daily1
SET nSalePrice = 1.01
WHERE nSalePrice IS NULL

DECLARE @err INT
SELECT @err = 0
BEGIN TRANSACTION
INSERT INTO tContractGoodsDaily (dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, nQty1,
                                 nAmount1, nNetAmount1, nQty2, nAmount2, nNetAmount2, sCategoryNO, sTradeModeID, dLastUpdateTime, nSalePrice, sPRSTypeID,
                                 nFinAmount1, nFinNetAmount1, nFinAmount2, nFinNetAmount2)
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
    sPRSTypeID,
    sum(nFinAmount1),
    sum(nFinNetAmount1),
    sum(nFinAmount2),
    sum(nFinNetAmount2)
  FROM #Daily1
  GROUP BY dTradeDate, sStoreNO, sContractNO, nGoodsID, nVendorID, sTypeID, sType, nTaxPct, sCategoryNO, sTradeModeID,
    nSalePrice, sPRSTypeID
SELECT @err = @err + @@error

UPDATE tSaleDisStoreGoods
SET nTag = nTag | 16
FROM tSaleDisStoreGoods AS a, #sd AS b
WHERE a.sPaperNO = b.sPaperNO AND a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID

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
    DROP TABLE #ConSale
    DROP TABLE #dis1
    DROP TABLE #dis2
    DROP TABLE #dis3
    DROP TABLE #sd
    DROP TABLE #adj1
    RAISERROR ( '插入数据出错', 16, 1)
    RETURN
  END

DROP TABLE #Daily1
DROP TABLE #Daily3
DROP TABLE #Batch
DROP TABLE #EndStock
DROP TABLE #ConSale
DROP TABLE #dis1
DROP TABLE #dis2
DROP TABLE #dis3
DROP TABLE #sd
DROP TABLE #adj1

END