SET QUOTED_IDENTIFIER OFF
SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[rj_Batch_SaleReturn]
    @StoreNO [varchar](4),
    @rq      [datetime]
AS
  BEGIN
    /*
    日结批次处理--销售退货
    --------------------------------------------------------------
    版本  3.1
    ------------------------------------------------------------
    1.01 修改：   -- 2006-11-01
      商品在tStockAccount有纪录，在tStoreGoods无记录时，会导致取不到税率，插入批次时报错。
      改为：这种情况下取税率为。
         在写批次修改纪录(tStockBatchLog)时，原来会把批次类型写成所取的有效批次的的批次类型，改为统一写为销售退货。
         增加处理流程说明
    1.10 修改：tStockBatch增加字段sTradeModeID用于记录交易方式。
    ----------------------------------------------------------------
    2.0 修改
    增加多店支持，增加批次的经营方式、合同号
    ------------------------------------------------------------
    2.1 修改 2013-05-12
    原来没考虑代营的退货，加上处理
    ------------------------------------------------------------
    2.2 修改2013-05-29
    销售批次改成逐条小票明细处理，处理结果放到tPosSaleCost表
    ----------------------------------------------------------
    2.3 修改2014-11-19
    原来过滤了批次价，现在去掉过滤
    ----------------------------------------------------------
    2.4 修改2014-01-17
    增加参数配置处理优先顺序，参数tSystemCtrl sCode='BatchSalePiority'，配置例子为'132'，含义：购销代销先进先出价格
    ----------------------------------------------------------
    2.5 修改2014-12-27
    批次优先顺序的时候，如果是已经被日结标为可清除的，优先级别低
    增加nPendingQty的判断
    ------------------------------------------------------------------
    2.6 修改2016-02-17
    代营商品的扣点，原来是从批次，改取tStoreGoodsVendor.nRealRatio
    --------------------------------------------------------
    2.7 修改 2017-03-11
    增加分仓处理，优先增加后仓批次。
    --------------------------------------------------------
    2.8 修改 2017-05-25
    增加储位信息, 查找储位信息一样的商品
    ------------------------------------------------------------
    2.9 修改2017-08-05
    如果有分割商品的退货，最后调用一下处理过程，把它处理到来源上面去
    ------------------------------------------------------------
    3.0 修改 2019-01-10
    分割品处理取消，分割品可以保留自己的批次
    修正组合商品退货写入tPosSaleCost的成分nGoodsID=0的问题
    ------------------------------------------------------------
    3.1 修改 2019-05-15
    不使用销售和亏损的批次
    -----------------------------------------------------------
    基本处理流程：
    begin
    |
    取待处理批次
    |
    查找对应商品的有效批次
    |
    如果找到有效批次
      begin
      |
        增加该批次的数量
      |
      end
    |
    找不到有效批次
      begin
      |
      新增加一个批次，类型为销售退货
      |
      end
    |
    end
    */

    DECLARE @TmpID NUMERIC(12) /* 待处理批次ID号，对应rj_TmpBatch.ID */
    DECLARE @DealDate DATETIME /* 处理日期*/
    DECLARE @GoodsID NUMERIC(8) /* 商品编码*/
    DECLARE @Qty NUMERIC(14, 3) /* 要处理的销售数量*/
    DECLARE @amt NUMERIC(14, 2) /* 要处理的销售金额*/
    DECLARE @OldBatchPrice NUMERIC(14, 4)   /* 要处理的旧销售批次的批次价*/
    DECLARE @BatchDate DATETIME /* 要处理的旧销售批次的批次日期*/
    DECLARE @NewBatchID NUMERIC(16) /* 可用批次的价格*/
    DECLARE @NewVendorID NUMERIC(8) /* 可用批次的供应商编码*/
    DECLARE @bq NUMERIC(14, 3) /* 可用批次数量*/
    DECLARE @NewBatchPrice NUMERIC(14, 4) /* 可用批次的批次价*/
    DECLARE @BatchTypeID VARCHAR(3) /* 批次类型标志*/
    DECLARE @BatchType VARCHAR(20) /* 批次类型*/
    DECLARE @Tax NUMERIC(6, 4) /* 税率*/
    DECLARE @o VARCHAR(80) /* 用于检测输出*/
    DECLARE @err INT /* 用于错误处理*/
    DECLARE @SerID NUMERIC(8) /* tStockBatchLog  的顺序号*/
    DECLARE @TradeModeID VARCHAR(10) /* 交易方式*/
    DECLARE @SalePrice NUMERIC(12, 2)
    DECLARE @ContractNO VARCHAR(20)
    DECLARE @Ratio NUMERIC(6, 4)
    DECLARE @BusinessTypeID VARCHAR(2)
    DECLARE @TradeDate DATETIME, @PosNO VARCHAR(3), @PosSerID NUMERIC(4), @PosItem NUMERIC(3), @PosSort INT
    DECLARE @PosSalePrice NUMERIC(12, 2), @DisAmount NUMERIC(12, 2), @CDis NUMERIC(12, 2), @SalesClerkNO VARCHAR(20), @CategoryNO VARCHAR(8), @CategoryID NUMERIC(8)
    DECLARE @CardNO VARCHAR(20)
    DECLARE @LocatorNO VARCHAR(20)
    DECLARE @Memo VARCHAR(40)

    SET NOCOUNT ON

    SELECT @err = 0

    SELECT @BatchType = sComDesc
    FROM tCommon
    WHERE sLangID = '936' AND sCommonNO = 'BATT' AND sComID = '10'

    SELECT @BusinessTypeID = sValue1
    FROM tSystemCtrl
    WHERE sCode = 'BusinessTypeID'

    /* 2.4 修改增加参数配置处理优先顺序，参数tSystemCtrl sCode='BatchSalePiority' */
    DECLARE @pi1 VARCHAR(1), @pi2 VARCHAR(1), @pi3 VARCHAR(1), @pi VARCHAR(20)
    DECLARE @Pior1 VARCHAR(40), @Pior2 VARCHAR(40), @Pior3 VARCHAR(40)
    SELECT @pi = sValue1
    FROM tSystemCtrl
    WHERE sCode = 'BatchSalePiority'
    IF isnull(@pi, '') NOT IN ('123', '132', '213', '231', '312', '321')
      SELECT @pi = '123'
    SELECT
        @pi1 = substring(@pi, 1, 1),
        @pi2 = substring(@pi, 2, 1),
        @pi3 = substring(@pi, 3, 1)

    /* 游标取待销售退货*/
    DECLARE cdeal CURSOR FOR SELECT
                               ID,
                               dDealDate,
                               nGoodsID,
                               nQty,
                               nBatchPrice,
                               sBatchTypeID,
                               dBatchDate,
                               nAmount,
                               sStoreNO,
                                 dTradeDate = dBatchDate,
                                 sPosNO = substring(sPaperNO, 1, 3),
                                 nSerID = convert(NUMERIC(4), substring(sPaperNO, 4, 4)),
                                 nItem = convert(NUMERIC(3), substring(sPaperNO, 8, 3)),
                               isnull(sLocatorNO, ''),
                               sOption
                             FROM rj_TmpBatch
                             WHERE dDealDate = @rq AND sBatchTypeID = '10' AND nLeftQty <> 0
    OPEN cdeal
    FETCH cdeal
    INTO @TmpID, @DealDate, @GoodsID, @Qty, @OldBatchPrice, @BatchTypeID, @BatchDate, @amt, @StoreNO,
      @TradeDate, @PosNO, @PosSerID, @PosItem, @LocatorNO, @Memo
    WHILE @@fetch_status = 0
      BEGIN

        /* 店号*/
        IF isnull(@StoreNO, '') = ''
          BEGIN
            RAISERROR ( '店号为空，请检查！', 16, 1)
            RETURN
          END

        /* 小票的信息，这个很烦，只能从小票里面现取了*/
        SELECT
            @PosSalePrice = NULL,
            @DisAmount = NULL,
            @SalesClerkNO = NULL,
            @CategoryNO = NULL,
            @CategoryID = NULL,
            @CardNO = NULL
        SELECT
            @PosSalePrice = round(nSalePrice, 2),
            @DisAmount = nDisAmount,
            @SalesClerkNO = sSalesClerkNO
        FROM tPosSaleDtl
        WHERE dTradeDate = @TradeDate AND sStoreNO = @StoreNO AND sPosNO = @PosNO AND nSerID = @PosSerID AND
              nItem = @PosItem
        SELECT @CardNO = sCardNO
        FROM tPosSale
        WHERE dTradeDate = @TradeDate AND sStoreNO = @StoreNO AND sPosNO = @PosNO AND nSerID = @PosSerID
        /* 分类或者柜组*/
        IF @BusinessTypeID = 'E'
          SELECT @CategoryNO = sOrgNO
          FROM tStoreGoodsOrg
          WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID
        ELSE
          BEGIN
            SELECT @CategoryID = nCategoryID
            FROM tGoods
            WHERE nGoodsID = @GoodsID
            SELECT @CategoryNO = sCategoryNO
            FROM tCategory
            WHERE nCategoryID = @CategoryID
          END

        SELECT
            @NewBatchPrice = NULL,
            @NewVendorID = NULL,
            @Tax = NULL,
            @NewBatchID = NULL

        /* 查找商品的正批次*/
        /* 2006-01-03 增加，如果批次可用数量为，但是有锁定数量，那么也加到该批次去，但优先处理有可用数量的批次*/
        /*v2.7 增加储位信息*/
        SET ROWCOUNT 1
        SELECT
            @StoreNO = sStoreNO,
            @NewBatchID = nBatchID,
            @NewBatchPrice = nBatchPrice,
            @Tax = nBuyTaxPct,
            @NewVendorID = nVendorID,
            @TradeModeID = sTradeModeID,
            @ContractNO = sContractNO,
            @Ratio = nRatio
        FROM tStockBatch
        WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID AND nActionQty + nLockedQty - nPendingQty >= 0 AND
              nBatchPrice >= 0
              AND isnull(sLocatorNO, '') = isnull(@LocatorNO, '') AND sBatchTypeID NOT IN ('3', '8')
        ORDER BY CASE WHEN (nActionQty = 0 AND nLockedQty = 0 AND isnull(sRecNO, '') LIKE '%可清除%')
          THEN 1
                 ELSE 0 END,
          CASE WHEN isnull(sLocatorNO, '') IN ('', '00')
            THEN 1
          ELSE 0 END
        SET ROWCOUNT 0

        BEGIN TRANSACTION /* 事务控制，每条记录独立一个事务*/

        IF @NewBatchID IS NOT NULL /* 存在相同批次，更改批次数量*/
          BEGIN
            /* 处理合同号*/
            IF @ContractNO IS NULL
              SELECT @ContractNO = sContractNO
              FROM tStoreGoodsVendor
              WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID AND nVendorID = @NewVendorID

            /* 代营的处理*/
            IF @TradeModeID = '6'
              BEGIN
                SELECT @Ratio = nRealRatio * 0.01
                FROM tStoreGoodsVendor
                WHERE sStoreNO = @StoreNO AND nVendorID = @NewVendorID AND nGoodsID = @GoodsID AND sTradeModeID = '6'
                SELECT @NewBatchPrice = ROUND(@amt * (1 - @Ratio) / @Qty, 4)
              END

            INSERT INTO rj_DealBatch (dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                                      nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                                      sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO,
                                      sLocatorNO)
            VALUES (@DealDate, @TmpID, 1, @NewBatchID, @BatchTypeID, @GoodsID,
                               @NewVendorID, @NewVendorID, @Qty, @amt, @OldBatchPrice, @NewBatchPrice,
                    @StoreNO, getdate(), @ContractNO, @TradeModeID, @Tax, NULL,
                    @LocatorNO)
            SELECT @err = @err + @@error

            UPDATE tStockBatch
            SET nActionQty = nActionQty + @Qty
            WHERE sStoreNO = @StoreNO AND nBatchID = @NewBatchID
            SELECT @err = @err + @@error

            /* 插入POS成本表*/
            SELECT @PosSort = NULL
            SELECT @PosSort = max(nSort) + 1
            FROM tPosSaleCost
            WHERE dTradeDate = @TradeDate AND sPosNO = @PosNO AND nSerID = @PosSerID AND nItem = @PosItem
            IF @PosSort IS NULL
              SELECT @PosSort = 1
            INSERT INTO tPosSaleCost (dTradeDate, sStoreNO, sPosNO, nSerID, nItem, nSort, nGoodsID, nSaleQty, nSalePrice,
                                      nSaleAmount, nDisAmount, sMemo, nSaleCost, nVendorID, sContractNO, nRatio, nTaxPct, sTradeModeID, dDailyDate,
                                      sSalesClerkNO, sCategoryNO, sCardNO, dLastUpdateTime)
            VALUES (@TradeDate, @StoreNO, @PosNO, @PosSerID, @PosItem, @PosSort, @GoodsID, -@Qty, @PosSalePrice,
                                -@amt, @DisAmount, @Memo, -round(@Qty * @NewBatchPrice, 2), @NewVendorID, @ContractNO,
                                                   @Ratio, @Tax, @TradeModeID, @rq,
                                                   @SalesClerkNO, @CategoryNO, @CardNO, getdate())
            SELECT @err = @err + @@error

            /* 取tStockBatchLog的最大序列号*/
            SELECT @SerID = NULL
            SELECT @SerID = max(nSerID) + 1
            FROM tStockBatchLog
            WHERE sStoreNO = @StoreNO AND nBatchID = @NewBatchID
            IF @SerID IS NULL
              SELECT @SerID = 1

            /* 插入tStockBatchLog */
            INSERT INTO tStockBatchLog (sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                        sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct,
                                        sLocatorNO)
            VALUES (@StoreNO, @NewBatchID, @SerID, @GoodsID, @NewVendorID, @BatchTypeID,
                              @BatchType, @Qty, @NewBatchPrice, @rq, 1, convert(VARCHAR, @rq, 112) + '010', @Tax,
                    @LocatorNO)
            SELECT @err = @err + @@error

          END
        ELSE /* 否则新增批次 */
          BEGIN
            EXEC up_GetBatchID @StoreNO, @NewBatchID OUTPUT /* 取批次号*/

            SELECT
                @NewVendorID = NULL,
                @NewBatchPrice = NULL,
                @Tax = NULL,
                @TradeModeID = NULL,
                @ContractNO = NULL,
                @Ratio = NULL

            /* 取进价，从主供应商  改成使用过程 */
            EXEC up_GetDefaultBuyPrice @GoodsID, @StoreNO, @ContractNO OUT, @NewVendorID OUT, @NewBatchPrice OUT,
                                       @TradeModeID OUT, @Tax OUT

            /* 代营处理 */
            IF @TradeModeID = '6' AND @NewBatchPrice > 0 AND @NewBatchPrice < 1
              BEGIN
                SELECT @Ratio = @NewBatchPrice
                /* select @SalePrice = nSalePrice from tStoreGoods where sStoreNO=@StoreNO and nGoodsID=@GoodsID */
                SELECT @NewBatchPrice = ROUND(@amt * (1 - @Ratio) / @Qty, 4)
              END

            INSERT INTO rj_DealBatch (dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                                      nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                                      sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO,
                                      sLocatorNO)
            VALUES (@DealDate, @TmpID, 0, @NewBatchID, @BatchTypeID, @GoodsID,
                               @NewVendorID, @NewVendorID, @Qty, @amt, @NewBatchPrice, @NewBatchPrice,
                    @StoreNO, getdate(), @ContractNO, @TradeModeID, @Tax, NULL,
                    @LocatorNO)
            SELECT @err = @err + @@error

            /* 插入POS成本表*/
            SELECT @PosSort = NULL
            SELECT @PosSort = max(nSort) + 1
            FROM tPosSaleCost
            WHERE dTradeDate = @TradeDate AND sPosNO = @PosNO AND nSerID = @PosSerID AND nItem = @PosItem
            IF @PosSort IS NULL
              SELECT @PosSort = 1

            INSERT INTO tPosSaleCost (dTradeDate, sStoreNO, sPosNO, nSerID, nItem, nSort, nGoodsID, nSaleQty, nSalePrice,
                                      nSaleAmount, nDisAmount, sMemo, nSaleCost, nVendorID, sContractNO, nRatio, nTaxPct, sTradeModeID, dDailyDate,
                                      sSalesClerkNO, sCategoryNO, sCardNO, dLastUpdateTime)
            VALUES (@TradeDate, @StoreNO, @PosNO, @PosSerID, @PosItem, @PosSort, @GoodsID, -@Qty, @PosSalePrice,
                                -@amt, @DisAmount, @Memo, -round(@Qty * @NewBatchPrice, 2), @NewVendorID, @ContractNO,
                                                   @Ratio, @Tax, @TradeModeID, @rq,
                                                   @SalesClerkNO, @CategoryNO, @CardNO, getdate())
            SELECT @err = @err + @@error

            /* 插入销售退货批次*/
            INSERT INTO tStockBatch (sStoreNO, nBatchID, nGoodsID, nVendorID, sBatchTypeID, sBatchType,
                                     nBatchQty, nBatchPrice, nActionQty, nLockedQty, nPendingQty, nPendingPrice, dBatchDate,
                                     dLastDownTime, nBuyTaxPct, sRecNO, nAmount, dLastUpdateTime, sTradeModeID, sContractNO, nRatio,
                                     sLocatorNO)
            VALUES (@StoreNO, @NewBatchID, @GoodsID, @NewVendorID, @BatchTypeID, @BatchType,
                              @Qty, @NewBatchPrice, @Qty, 0, 0, @NewBatchPrice, @rq,
                                                                getdate(), @Tax, convert(VARCHAR, @rq, 112) + '010',
                                                                NULL, getdate(), @TradeModeID, @ContractNO, @Ratio,
                    @LocatorNO)
            SELECT @err = @err + @@error

            /* 取tStockBatchLog的最大序列*/
            SELECT @SerID = NULL
            SELECT @SerID = max(nSerID) + 1
            FROM tStockBatchLog
            WHERE sStoreNO = @StoreNO AND nBatchID = @NewBatchID
            IF @SerID IS NULL
              SELECT @SerID = 1
            /* 插入tStockBatchLog */
            INSERT INTO tStockBatchLog (sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                        sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct,
                                        sLocatorNO)
            VALUES (@StoreNO, @NewBatchID, @SerID, @GoodsID, @NewVendorID, @BatchTypeID,
                              @BatchType, @Qty, @NewBatchPrice, @rq, 1, convert(VARCHAR, @rq, 112) + '003', @Tax,
                    @LocatorNO)
            SELECT @err = @err + @@error

          END

        /* 待处理数量清零*/
        UPDATE rj_TmpBatch
        SET nLeftQty = 0, nLeftAmount = 0
        WHERE ID = @TmpID
        SELECT @err = @err + @@error

        SELECT
            @Qty = 0,
            @amt = 0
        IF @err = 0
          COMMIT TRANSACTION
        ELSE
          BEGIN
            ROLLBACK TRANSACTION
            RETURN 1
          END

        FETCH cdeal
        INTO @TmpID, @DealDate, @GoodsID, @Qty, @OldBatchPrice, @BatchTypeID, @BatchDate, @amt, @StoreNO,
          @TradeDate, @PosNO, @PosSerID, @PosItem, @LocatorNO, @Memo

      END

    CLOSE cdeal
    DEALLOCATE cdeal

  END

GO