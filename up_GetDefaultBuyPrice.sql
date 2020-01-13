ALTER PROCEDURE [dbo].[up_GetDefaultBuyPrice]
@GoodsID [numeric](8, 0),
@StoreNO [varchar](8),
@ContractNO [varchar](20) OUTPUT,
@VendorID [numeric](8, 0) OUTPUT,
@BuyPrice [numeric](12, 4) OUTPUT,
@TradeModeID [varchar](4) OUTPUT,
@Tax [numeric](7, 5) OUTPUT
AS
BEGIN
  /****************************************************
  获取商品默认进价的过程
  版本  1.6
  创建日期  2015-03-09
  ------------------------------------------
  1.1 修改 2016-03-04
  代营商品的，有些客户不做进货（不进货还做什么代营？？？？），没批次的情况下，取的就是默认扣点，然后后来进货又重新计算成本调整，一塌糊涂
  没批次的，如果取到的默认供应商是代营，那么使用nRealRatio而不是nRatio
  ----------------------------------------
  1.2 修改 2018-09-16
  有些情况取不到税率，判断一下
  ----------------------------------------
  1.3 修改 2018-12-02
  默认价优先取最后进价
  ----------------------------------------
  1.4 修改 2018-12-29
  分割品的默认价取最后成本价
  ----------------------------------------
  1.5 修改 2019-01-21
  先把合同之类的清空再取值
  ----------------------------------------
  1.6 修改 2019-01-24
  tStockAccount如果最后进价是负数，忽略
  ****************************************************/
  DECLARE @o VARCHAR(200)
  SELECT
    @VendorID = NULL,
    @ContractNO = NULL,
    @BuyPrice = NULL,
    @TradeModeID = NULL,
    @Tax = NULL
  -- 优先取最后进价
  IF exists(SELECT 1
            FROM tStoreGoodsOtherInfo
            WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID AND sTypeID = 'LastCost')
    BEGIN
      SELECT
        @BuyPrice = nValue1,
        @VendorID = nVendorID,
        @ContractNO = sContractNO,
        @TradeModeID = sValue1,
        @Tax = nValue2
      FROM tStoreGoodsOtherInfo
      WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID AND sTypeID = 'LastCost'
      RETURN
    END

  SELECT
    @BuyPrice = nLastBuyPrice,
    @VendorID = nLastVendorID
  FROM tStockAccount
  WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID
        AND isnull(nLastBuyPrice, 0) <> 0

  IF @BuyPrice > 0 AND @VendorID IS NOT NULL
    BEGIN
      SELECT
        @Tax = isnull(nBuyTaxPct, 1),
        @ContractNO = sContractNO,
        @TradeModeID = sTradeModeID
      FROM tStoreGoodsVendor
      WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID AND nVendorID = @VendorID
      -- 没有供应商商品记录，尝试去合同

      IF @ContractNO IS NULL
        SELECT TOP 1
          @ContractNO = a.sContractNO,
          @TradeModeID = a.sTradeModeID,
          @Tax = a.nBuyTaxRate * 0.01 + 1
        FROM tContract AS a, tContractGoods AS b
        WHERE a.sContractNO = b.sContractNO AND a.nTag & 3 = 2 AND b.nTag & 1 = 0
              AND a.nVendorID = @VendorID AND b.nGoodsID = @GoodsID

      -- select @o='Get Price 01'+',VendorID='+convert(varchar, @VendorID)+',ContractNO='+isnull(@ContractNO, '999999')
      -- print @o

      IF @ContractNO IS NULL
        SELECT TOP 1
          @ContractNO = sContractNO,
          @TradeModeID = sTradeModeID,
          @Tax = nBuyTaxRate * 0.01 + 1
        FROM tContract
        WHERE nTag & 3 = 2 AND nVendorID = @VendorID
      -- 最后进价对应的没有供应商商品记录，放弃
      IF @ContractNO IS NULL
        SELECT
          @BuyPrice = NULL,
          @VendorID = NULL
    END
  -- 没有最后进价，还是先设置null
  ELSE SELECT
         @BuyPrice = NULL,
         @VendorID = NULL

  /* 主供应商 */
  IF @BuyPrice IS NULL
    BEGIN
      -- print 'Get Price 02, Default BuyPrice'
      SELECT
        @BuyPrice = CASE WHEN v.sTradeModeID = '6'
          THEN nRealRatio * 0.01
                    ELSE v.nRealBuyPrice END,
        @VendorID = v.nVendorID,
        @Tax = isnull(nBuyTaxPct, 1),
        @ContractNO = v.sContractNO,
        @TradeModeID = v.sTradeModeID
      FROM tStoreGoodsVendor AS v, tStoreGoods AS g
      WHERE v.sStoreNO = g.sStoreNO AND v.nGoodsID = g.nGoodsID AND v.nVendorID = g.nMainVendorID
            AND g.sStoreNO = @StoreNO AND g.nGoodsID = @GoodsID

    END
  /* 无主供应商进价记录，随便找一个供应商*/
  IF @BuyPrice IS NULL
    SELECT
      @BuyPrice = CASE WHEN v.sTradeModeID = '6'
        THEN nRealRatio * 0.01
                  ELSE v.nRealBuyPrice END,
      @VendorID = v.nVendorID,
      @Tax = isnull(nBuyTaxPct, 1),
      @ContractNO = v.sContractNO,
      @TradeModeID = v.sTradeModeID
    FROM tStoreGoodsVendor AS v, tStoreGoods AS g
    WHERE v.sStoreNO = g.sStoreNO AND v.nGoodsID = g.nGoodsID
          AND g.sStoreNO = @StoreNO AND g.nGoodsID = @GoodsID
    ORDER BY v.sTradeModeID DESC, v.dLastUpdateTime ASC

  /* 无供应商进价记录，取库存平均价作为成本*/
  IF @BuyPrice IS NULL
    BEGIN
      SELECT
        @BuyPrice = nAvgStockPrice,
        @VendorID = 999999,
        @ContractNO = '999901',
        @TradeModeID = '1'
      FROM tStockAccount
      WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID
      SELECT @Tax = isnull(nSaleTaxPct, 1)
      FROM tStoreGoods
      WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID
      SELECT @Tax = isnull(@Tax, 1)
    END

  /* 无库存记录，取平均售价作为成本*/
  IF @BuyPrice IS NULL
    SELECT
      @Tax = isnull(nSaleTaxPct, 1),
      @BuyPrice = nSalePrice,
      @VendorID = 999999,
      @ContractNO = '999901',
      @TradeModeID = '1',
      @Tax = 1
    FROM tStoreGoods
    WHERE sStoreNO = @StoreNO AND nGoodsID = @GoodsID

  /* 如果商品在tStoreGoods无记录，则取不到税率，设置税率为*/
  IF @BuyPrice IS NULL
    SELECT
      @Tax = nSaleTaxRate * 0.01 + 1,
      @BuyPrice = nSalePrice,
      @VendorID = 999999,
      @ContractNO = '999901',
      @TradeModeID = '1'
    FROM tGoods
    WHERE nGoodsID = @GoodsID

  SELECT @Tax = isnull(@Tax, 1)

  IF @BuyPrice IS NULL
    SELECT
      @BuyPrice = 0,
      @VendorID = 999999,
      @ContractNO = '999901',
      @TradeModeID = '1',
      @Tax = 1

END