CREATE PROCEDURE [dbo].[up_DealBatchSale_RealTime]
    @StoreNO [varchar](4),
    @rq      [datetime] = NULL
AS
  BEGIN
    /****************************************************************
    版本 4.6
    把生鲜分割、组合商品、更新库存的步骤，都写到批次处理里面了
    这个仅做批次初始化
    ----------------------------------------
    4.1 修改 2018-04-19
    增加了双计量的处理
    双计量规则：
    1. POS销售明细会另传一个称重值的字段nWieghtQty上来，要求此字段不为0，才能使用双计量
    2. 使用双计量的商品，只能是标准、计量、或者价格商品
    3. 商品具有【销售双计量】属性(tGoods.nProperty1 & 128 = 128)
    ----------------------------------------
    4.2 修改 2018-12-23
    双计量的处理，增加一下判断，有有效数量(>0.1)再说
    ---------------------------------------
    4.3 修改 2019-06-21
    发现可能会有组合商品成分表暂时没有记录的问题，增加以下判断，如果有组合商品，但是成分表没记录的，等待5秒
    ----------------------------------------
    4.4 修改 2019-08-07
    还是组合商品问题，没组合成份先报错退出吧
    ----------------------------------------
    4.5 修改 2019-09-11
    双计量的,增加一下重量上限的判断
    ----------------------------------------
    4.6 修改 2019-10-24
    tPosSale增加dUploadTime
    ****************************************************************/
    /* 把日期在日结日之前，未日结处理的POS小票单头打上日结日标志 */
    DECLARE @vartime VARCHAR(20)
    DECLARE @cdate DATETIME, @ctime DATETIME, @utime DATETIME
    DECLARE @err INT, @row INT, @i INT, @status VARCHAR(8), @retstatus INT
    DECLARE @code VARCHAR(20)
    DECLARE @sid VARCHAR(20)
    SELECT
        @err = 0,
        @i = 1,
        @row = 0,
        @code = 'DealBatchSale'
    SELECT @cdate = convert(DATETIME, convert(VARCHAR, getdate(), 111))
    IF @rq IS NULL
      SELECT @rq = @cdate
    ELSE SELECT @cdate = @rq
    /* 判断tRunListStatus.nSerID，是否已经日结处理销售批次，如果是，退出 */

    IF exists(SELECT 1
              FROM tRunListStatus
              WHERE dTradeDate = @rq AND nSerID > 259)
      BEGIN
        RETURN
      END

    /* 获取每次的ID */

    SELECT @sid = convert(VARCHAR(8), getdate(), 112) + replace(convert(VARCHAR, getdate(), 108), ':', '') +
                  substring(convert(VARCHAR, rand(datediff(SS, '2000-1-1', getdate()))), 4, 6)

    SELECT @vartime = convert(VARCHAR, getdate(), 111) + ' ' + convert(VARCHAR, getdate(), 108)

    SELECT @ctime = convert(DATETIME, @vartime)


    IF NOT exists(SELECT 1
                  FROM tSystemVar
                  WHERE sCode = @code)
      BEGIN
        INSERT INTO tSystemVar
        (sCode, sDesc, sValue, sUpLim, sStep, nTag, sCreateUser, dCreateDate, sChangeUser, dChangeDate, sConfirmUser, dConfirmDate, dLastUpdateTime)
        VALUES
          (@code, '实时销售批次处理', '0', '0', '0', 4, 'Admin', '2009-07-08 21:56:55.170', 'Admin', '2012-09-12 23:08:10.327',
                  NULL, NULL, '2009-07-08 21:56:55.170')

      END
    SELECT
        @status = sValue,
        @utime = dLastUpdateTime
    FROM tSystemVar
    WHERE sCode = @code

    /*1.当前未在处理中...*/
    IF @status = '0' OR datediff(MI, @utime, getdate()) > 30
      BEGIN
        /* 增加事务控制 */

        BEGIN TRANSACTION

        UPDATE tSystemVar
        SET sValue = '1'
        WHERE sCode = @code

        SELECT @err = @err + @@error



        /* 取得单头 */

        INSERT INTO tSaleBatch_Tmp1

        (sID, sStoreNO, dTradeDate, sPosNO, nSerID, nSaleAmount, nTradeType, nTradeStatus, sCardNO)

          SELECT
            @sid,
            sStoreNO,
            dTradeDate,
            sPosNO,
            nSerID,
            nSaleAmount,
            nTradeType,
            nTradeStatus,
            sCardNO

          FROM tPosSale

          WHERE (@StoreNO = '' OR (@StoreNO <> '' AND sStoreNO = @StoreNO))  /*在这里限制分店就可以了*/

                AND dUpdate IS NULL AND isnull(sSaleRetReason, '') = ''

                AND dTradeDate < dateadd(DD, 1, @rq)

                --AND sStoreNO!='0001'  ----2018-7-25 BRIN 销售库存服务

                AND dTradeDate >= dateadd(MM, -2, @rq)

                AND NOT exists(SELECT 1
                               FROM tCommon

                               WHERE sCommonNO = 'SaleTurnType'

                                     AND convert(INT, nNum1) NOT IN (0, 2)

                                     AND tPosSale.nTradeType = convert(INT, nNum1)

          )  --排除掉销售单转换类型 2015-4-7

        SELECT @err = @err + @@error



        -- 4.1 增加，双计量处理

        UPDATE tPosSaleDtl
        SET nOrgQty = pd.nSaleQty, nSaleQty = pd.nWeightQty, dLastUpdateTime = getdate()

        FROM tSaleBatch_Tmp1 AS p, tPosSaleDtl AS pd WITH ( INDEX = PK_TPOSSALEDTL), tGoods AS g

WHERE p.sID=@sid AND p.sStoreNO=pd.sStoreNO AND p.dTradeDate=pd.dTradeDate

AND p.sPosNO=pd.sPosNO AND p.nSerID=pd.nSerID

AND g.nGoodsID = pd.nGoodsID AND g.sGoodTypeID IN ('S', 'P', 'Q') AND g.nProperty1 & 128 = 128

AND isnull(pd.nWeightQty, 0)>=0.1 AND isnull(pd.nWeightQty, 0)<=30 AND pd.nOrgQty IS NULL AND round(pd.nSaleQty, 0)=pd.nSaleQty

SELECT @err = @err + @@error



/* 把单体数据，插入临时表 */

/* 版本2.2 增加组合商品支持，这个表要加个nSort字段 */

INSERT INTO tSaleBatch_Tmp2 (sID, sStoreNO, dTradeDate, sPosNO, nSerID, nItem, nSort, nGoodsID, nSaleQty, nSaleAmount, nDisAmount, nSalePrice,

                             sSalesClerkNO, sCategoryNO, sTradeModeID, nVendorID, sContractNO, nRatio, nSaleCost, nTaxPct, sCardNO)

  SELECT
    @sid,
    pd.sStoreNO,
    pd.dTradeDate,
    pd.sPosNO,
    pd.nSerID,
    pd.nItem,
    0,
    pd.nGoodsID,
    pd.nSaleQty,
    pd.nSaleAmount,
    pd.nDisAmount,
    pd.nSalePrice,

    pd.sSalesClerkNO,
    '',
    '1',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    p.sCardNO

  FROM tSaleBatch_Tmp1 AS p, tPosSaleDtl AS pd WITH ( INDEX = PK_TPOSSALEDTL)

WHERE p.sID=@sid AND p.sStoreNO=pd.sStoreNO AND p.dTradeDate=pd.dTradeDate

AND p.sPosNO=pd.sPosNO AND p.nSerID=pd.nSerID

AND p.nTradeType IN (0, 2) AND p.nTradeStatus = 2

SELECT @err = @err + @@error



/* 根据业态类型更新sCategoryNO */

IF exists(SELECT 1
          FROM tSystemCtrl
          WHERE sCode = 'BusinessTypeID' AND sValue1 = 'E')

  UPDATE tSaleBatch_Tmp2
  SET sCategoryNO = b.sOrgNO FROM tSaleBatch_Tmp2 AS a, tStoreGoodsOrg AS b
  WHERE a.sID = @sid AND a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID

ELSE

  UPDATE tSaleBatch_Tmp2
  SET sCategoryNO = c.sCategoryNO FROM tSaleBatch_Tmp2 AS a, tGoods AS b, tCategory AS c
  WHERE a.sID = @sid AND a.nGoodsID = b.nGoodsID AND b.nCategoryID = c.nCategoryID

SELECT @err = @err + @@error



/* 联营专柜的按照扣点计算 */

UPDATE tSaleBatch_Tmp2
SET sTradeModeID = b.sTradeModeID, nVendorID = b.nMainVendorID, nRatio = c.nRealRatio, sContractNO = c.sContractNO,

  nSaleCost      = round(a.nSaleAmount * (1 - c.nRealRatio * 0.01), 2), nTaxPct = c.nBuyTaxPct

FROM tSaleBatch_Tmp2 AS a, tStoreGoods AS b, tStoreGoodsVendor AS c

WHERE a.sID = @sid AND a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID

      AND b.sStoreNO = c.sStoreNO AND b.nGoodsID = c.nGoodsID AND b.nMainVendorID = c.nVendorID

      AND c.sTradeModeID IN ('2', '3')

SELECT @err = @err + @@error



/* 联营专柜的插入POS小票成本表tPosSaleCost */

INSERT INTO tPosSaleCost (dTradeDate, sStoreNO, sPosNO, nSerID, nItem, nSort, nGoodsID, nSaleQty, nSalePrice,

                          nSaleAmount, nDisAmount, sMemo, nSaleCost, nVendorID, sContractNO, nRatio, nTaxPct, sTradeModeID, dDailyDate,

                          sSalesClerkNO, sCategoryNO, sCardNO, dLastUpdateTime)

  SELECT
    dTradeDate,
    sStoreNO,
    sPosNO,
    nSerID,
    nItem,
    1,
    nGoodsID,
    nSaleQty,
    round(nSalePrice, 2),

    nSaleAmount,
    nDisAmount,
    NULL,
    nSaleCost,
    nVendorID,
    sContractNO,
    nRatio,
    nTaxPct,
    sTradeModeID,
    @rq,

    sSalesClerkNO,
    sCategoryNO,
    sCardNO,
    getdate()

  FROM tSaleBatch_Tmp2
  WHERE sID = @sid AND sTradeModeID IN ('2', '3')

SELECT @err = @err + @@error



-- 版本 4.4，这里加判断组合商品成分表没记录的，报错

IF exists(SELECT 1
          FROM tSaleBatch_Tmp2 a, tGoods b
          WHERE a.sID = @sid AND a.nSort = 0 AND a.nGoodsID = b.nGoodsID AND b.sGoodTypeID = 'C'

                AND NOT exists(SELECT 1
                               FROM tComplexElement AS c
                               WHERE b.nGoodsID = c.nGoodsID AND c.nTag & 1 = 0)

)

  BEGIN

    DECLARE @msg1 VARCHAR(400)

    SELECT TOP 1 @msg1 = b.sGoodsNO + '.' + b.sGoodsDesc + '是组合商品，但是没有成分记录。'
    FROM tSaleBatch_Tmp2 a, tGoods b
    WHERE a.sID = @sid AND a.nSort = 0 AND a.nGoodsID = b.nGoodsID AND b.sGoodTypeID = 'C'

          AND NOT exists(SELECT 1
                         FROM tComplexElement AS c
                         WHERE b.nGoodsID = c.nGoodsID AND c.nTag & 1 = 0)

    ROLLBACK

    RAISERROR (@msg1, 16, 1)

    RETURN

  END



/* 2.2 增加 组合商品插入POS小票成本表tPosSaleCost，nSaleAmount为0，用nSalePrice记录nSaleAmount */

INSERT INTO tPosSaleCost (dTradeDate, sStoreNO, sPosNO, nSerID, nItem, nSort, nGoodsID, nSaleQty, nSalePrice,

                          nSaleAmount, nDisAmount, sMemo, nSaleCost, nVendorID, sContractNO, nRatio, nTaxPct, sTradeModeID, dDailyDate,

                          sSalesClerkNO, sCategoryNO, sCardNO, dLastUpdateTime)

  SELECT
    dTradeDate,
    sStoreNO,
    sPosNO,
    nSerID,
    nItem,
    0,
    nGoodsID,
    nSaleQty,
    round(nSalePrice, 2),

    nSaleAmount,
    nDisAmount,
    '组合商品已拆分',
    0,
    0,
    '',
    NULL,
    1,
    '5',
    @rq,

    sSalesClerkNO,
    sCategoryNO,
    sCardNO,
    getdate()

  FROM tSaleBatch_Tmp2 a
  WHERE sID = @sid AND nSort = 0 AND exists(SELECT 1
                                            FROM tGoods AS b, tComplexElement AS c

                                            WHERE a.nGoodsID = b.nGoodsID AND b.sGoodTypeID = 'C' AND
                                                  a.nGoodsID = c.nGoodsID AND c.nTag & 1 = 0)

SELECT @err = @err + @@error


DELETE FROM tSaleBatch_Tmp2
WHERE sID = @sid AND sTradeModeID IN ('2', '3')

SELECT @err = @err + @@error



/* 销售退货插入待处理批次表

2013-05-29 修改 sPaperNO 记录小票号+nItem，dBatchDate记录小票dTradeDate */

INSERT INTO rj_TmpBatch (dDealDate, nBatchID, nGoodsID, nVendorID, sBatchTypeID, nQty,

                         nRetQty, nLeftQty, nAmount, nLeftAmount, nBatchPrice, dBatchDate, sPaperNO,

                         sStoreNO, dLastUpdateTime, nPrice1, sContractNO, sTradeModeID, nTaxPct)

  SELECT
    @rq,
    NULL,
    nGoodsID,
    NULL,
    '10',
    -nSaleQty,

    NULL,
    -nSaleQty,
    -nSaleAmount,
    -nSaleAmount,
    NULL,
    dTradeDate,
    sPosNO + substring(convert(VARCHAR, 10000 + nSerID), 2, 4) + substring(convert(VARCHAR, 1000 + nItem), 2, 3),

    sStoreNO,
    getdate(),
    CASE WHEN nSort >= 100
      THEN 1
    ELSE NULL END,
    NULL,
    NULL,
    NULL

  FROM tSaleBatch_Tmp2
  WHERE sID = @sid AND nSaleQty < 0 OR (nSaleQty = 0 AND nSaleAmount < 0)

SELECT @err = @err + @@error



/* 销售插入待处理批次表 */

INSERT INTO rj_TmpBatch (dDealDate, nBatchID, nGoodsID, nVendorID, sBatchTypeID, nQty,

                         nRetQty, nLeftQty, nAmount, nLeftAmount, nBatchPrice, dBatchDate, sPaperNO,

                         sStoreNO, dLastUpdateTime, nPrice1, sContractNO, sTradeModeID, nTaxPct)

  SELECT
    @rq,
    NULL,
    nGoodsID,
    NULL,
    '3',
    -nSaleQty,

    NULL,
    -nSaleQty,
    -nSaleAmount,
    -nSaleAmount,
    NULL,
    dTradeDate,
    sPosNO + substring(convert(VARCHAR, 10000 + nSerID), 2, 4) + substring(convert(VARCHAR, 1000 + nItem), 2, 3),

    sStoreNO,
    getdate(),
    CASE WHEN nSort >= 100
      THEN 1
    ELSE NULL END,
    NULL,
    NULL,
    NULL

  FROM tSaleBatch_Tmp2
  WHERE sID = @sid AND nSaleQty > 0 OR (nSaleQty = 0 AND nSaleAmount > 0)

SELECT @err = @err + @@error



/* 打上处理标志 */

UPDATE tPosSale
SET sSaleRetReason = @vartime, dUpdate = @rq, dUploadTime = getdate(), dLastUpdateTime = getdate()

FROM tSaleBatch_Tmp1 AS p, tPosSale AS ps WITH ( INDEX = PK_TPOSSALE)

WHERE p.sID=@sid AND p.sStoreNO=ps.sStoreNO AND p.dTradeDate=ps.dTradeDate

AND p.sPosNO=ps.sPosNO AND p.nSerID = ps.nSerID

SELECT @err = @err + @@error



/* 把POS小票收款记录打上日结日标志 */

UPDATE tPosPayt
SET dUpdate = @rq, dLastUpdateTime = getdate() FROM tPosPayt AS d WITH ( INDEX = PK_TPOSPAYT), tSaleBatch_Tmp1 AS p

WHERE p.sID=@sid AND p.sStoreNO= D.sStoreNO AND p.dTradeDate= D.dTradeDate AND p.sPosNO= D.sPosNO

AND p.nSerID= D.nSerID

SELECT @err = @err + @@error



/* 把POS小票明细打上日结日标志 */

UPDATE tPosSaleDtl
SET dUpdate = @rq, dLastUpdateTime = getdate()

FROM tPosSaleDtl AS d WITH ( INDEX = PK_TPOSSALEDTL), tSaleBatch_Tmp1 AS p

WHERE p.sID=@sid AND p.sStoreNO= D.sStoreNO AND p.dTradeDate= D.dTradeDate AND p.sPosNO= D.sPosNO

AND p.nSerID= D.nSerID

SELECT @err = @err + @@error


UPDATE tSystemVar
SET sValue = '0', dLastUpdateTime = getdate()
WHERE sCode = @code

SELECT @err = @err + @@error


DELETE FROM tSaleBatch_Tmp1
WHERE sID = @sid

SELECT @err = @err + @@error


DELETE FROM tSaleBatch_Tmp2
WHERE sID = @sid

SELECT @err = @err + @@error


DELETE FROM tSaleBatch_Tmp3
WHERE sID = @sid

SELECT @err = @err + @@error


IF @err <> 0

  BEGIN

    ROLLBACK TRANSACTION

    RETURN 1

  END

ELSE

  BEGIN

    COMMIT TRANSACTION

    EXEC @retstatus = up_DealBatch_RealTime @code, @StoreNO, @cdate

    RETURN @retstatus

  END


END

/*1.END.当前未在处理中...*/



ELSE

RETURN 2

END
