ALTER FUNCTION dbo.fn_IsFreshSplitDataOK(@StoreNO VARCHAR(20), @GoodsID NUMERIC(8))
RETURNS BIT
AS
BEGIN
  /****************************
  判断生鲜分割资料是否完整
  版本 1.0
  -------------------------------
  基本判断原则：
  1. 分割品、来源的商品资料属性要求正常，分割品nTag&2048=2048，来源nTag&512=512，非删除
  2. 分割品和来源的关系要有tFreshGoodsSplit.nTag&1=0
  3. 分割品、来源要求对分店有效，有正常商品供应商关系，且不是联营商品
  ****************************/
  DECLARE @IsFreshSplit BIT = 0
  -- 分割品属性
  IF NOT exists(SELECT 1
                FROM tGoods
                WHERE nGoodsID = @GoodsID AND nTag & 2049 = 2048)
    RETURN @IsFreshSplit

  -- 存放来源ID的变量表
  DECLARE @pa TABLE(nParentID NUMERIC(8))
  INSERT INTO @pa(nParentID) SELECT nParentID
                             FROM tFreshGoodsSplit
                             WHERE nGoodsID = @GoodsID AND nTag & 1 = 0

  -- 来源属性
  IF NOT exists(SELECT 1
                FROM @pa AS a, tGoods AS g
                WHERE a.nParentID = g.nGoodsID AND g.nTag & 513 = 512)
    RETURN @IsFreshSplit

  -- 分割品的分店供应商资料关系
  IF NOT exists(SELECT 1
                FROM tStoreGoods AS a, tStoreGoodsVendor AS b
                WHERE a.sStoreNO = @StoreNO AND a.nGoodsID = @GoodsID
                      AND a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.nMainVendorID = b.nVendorID AND
                      b.nTag & 1 = 0
                      AND b.sTradeModeID NOT IN ('2', '3'))
    RETURN @IsFreshSplit

  -- 来源的供应商商品关系
  IF NOT exists(SELECT 1
                FROM tStoreGoods AS a, tStoreGoodsVendor AS b, @pa AS p
                WHERE a.sStoreNO = @StoreNO AND a.nGoodsID = p.nParentID
                      AND a.sStoreNO = b.sStoreNO AND a.nGoodsID = b.nGoodsID AND a.nMainVendorID = b.nVendorID AND
                      b.nTag & 1 = 0
                      AND b.sTradeModeID NOT IN ('2', '3'))
    RETURN @IsFreshSplit

  SELECT @IsFreshSplit = 1
  RETURN @IsFreshSplit

END