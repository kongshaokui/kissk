ALTER PROCEDURE [dbo].[rj_Batch_MakeSplit]
  @rq datetime,
  @StoreNO [varchar](8),
  @GoodsID [numeric](8, 0),
  @Qty [numeric](12, 3),
  @PaperNO [varchar](16),
  @TmpID int,
  @SaleAmount numeric(16,2),
  @Status [smallint] OUTPUT,
  @Msg [varchar](200) OUTPUT
AS
begin
  /***************************************
  从来源生成分割商品
  版本  1.1
  ------------------------------------------
  根据分割商品的来源，生成分割品批次，支持多来源，按照先进先出原则
  --------------
  1.1 修改 2019-01-11
  增加不同来源不同比例的支持吧
  ***************************************/
  declare @o varchar(200)
  declare @IsSale int = 0  -- 是否销售产生的

  if @SaleAmount>0 select @IsSale = 1

  if @Qty<=0
    begin
      select @Status=1, @Msg='数量需>0'
      print @Msg
      return
    end

  if not exists(select 1 from tGoods as g1, tGoods as g2, tFreshGoodsSplit as b
  where b.nGoodsID=@GoodsID and b.nGoodsID=g1.nGoodsID and g1.nTag&(2048+1)=2048
        and b.nParentID=g2.nGoodsID and g2.nTag&(512+1)=512 and b.nTag&1=0
  )
    begin
      select @Status=2, @Msg='无分割商品设定，或商品已删除'
      print @Msg
      return
    end

  declare @ParentQty numeric(12,3),   /* 来源需要数量 */
  @ParentID numeric(8),   /* 来源ID */
  @BatchID numeric(16),
  @Ratio numeric(8,4), -- 分割比例
  @RatioCount int,  -- 多母商品的时候，分割比例的计数
  @NewBatchID numeric(16),
  @ActionQty numeric(12,3),
  @CQty numeric(12,3),
  @ThisSaleAmount numeric(12,2),
  @BatchPrice numeric(12,4),
  @AvgSalePrice numeric(14,2),
  @ContractNO varchar(20),
  @VendorID numeric(8),
  @TradeModeID varchar(4),
  @Tax numeric(7,5),
  @BatchTypeID varchar(10),
  @Amount numeric(12,2),   /* 分割品的总成本金额 */
  @ThisQty numeric(12,3),   /* 本批次对应的分割品数量 */
  @ThisPrice numeric(12,4),   /* 本批次对应的分割品价格 */
  @err int

  /* 过程要在事务内执行，不能用临时表，因为要嵌套调用，又不能用游标（sql server同一线程内游标名不能重复），
  懒得加表，就用表值变量了 */
  declare @csp table (nID int identity, nParentID numeric(8), sBatchTypeID varchar(10), nBatchID numeric(16), nActionQty numeric(12,3), nBatchPrice numeric(16,4),
  nVendorID numeric(8), sContractNO varchar(20), sTradeModeID varchar(4), nTaxPct numeric(7,5), nRatio numeric(8,4))
  insert into @csp(nParentID, sBatchTypeID, nBatchID, nActionQty, nBatchPrice, nVendorID, sContractNO, sTradeModeID, nTaxPct, nRatio)
    select a.nParentID, b.sBatchTypeID, b.nBatchID, b.nActionQty, b.nBatchPrice, b.nVendorID, b.sContractNO, b.sTradeModeID, b.nBuyTaxPct, a.nRatio
    from tFreshGoodsSplit as a, tStockBatch as b
    where a.nGoodsID=@GoodsID and nTag&1=0 and b.sStoreNO=@StoreNO and b.nGoodsID=a.nParentID
          and b.nActionQty>0
    order by b.dBatchDate, b.nBatchID

  select @AvgSalePrice = round(@SaleAmount/@Qty,2)

  declare @ci int, @cm int
  select @err=0
  begin transaction

  select @ci=1
  select @cm=max(nID) from @csp
  select @cm=isnull(@cm, 0)

  -- 下面的判断很搞，主要是有出现分割品卖了0.001，然后比例>1，这样算起来的来源，就是0，但是如果什么都不处理，分割品就没有批次了，
  -- 先不管那么多，如果是第一次进行循环，无论如何也进入一次再说，暂时这样处理吧
  while @ci<=@cm+1 and (@Qty>0 or @ci=1)
    /* 循环取来源的批次，直到分割完毕，或者没有批次 */
    begin  -- 01 begin
      -- 这里懒得后面再加其他的判断处理了，批次不够（循环导最大ID+1就是了）的直接在这里处理
      if @ci = @cm+1
        begin  -- 01AA begin

          -- 如果母商品曾经有进货，直接就用上次取得的最后进货信息，否则通过过程获取
          if @ContractNO is null or (isnull(@BatchTypeID,'5')='5')
            begin
              -- 先找一个母商品
              select top 1 @ParentID = nParentID, @Ratio=nRatio from tFreshGoodsSplit where nGoodsID=@GoodsID and nTag&1=0
              select @o='Old Data，ParentID=' +convert(varchar, @ParentID)+',ContractNO='+@ContractNO+',Price='+convert(varchar, @BatchPrice)
                        + ',VendorID='+ Convert(varchar, @VendorID)
              print @o
              exec up_GetDefaultBuyPrice @ParentID, @StoreNO, @ContractNO out, @VendorID out, @BatchPrice out, @TradeModeID out, @Tax out
            end

          select @ParentQty = round(@Qty/@Ratio, 3)
          select @o='ci='+Convert(varchar, @ci)+' && 获取默认母商品价，ParentID=' +convert(varchar, @ParentID)+',ContractNO='+@ContractNO+',Price='+convert(varchar, @BatchPrice)
                    + ',VendorID='+ Convert(varchar, @VendorID)
          print @o

          if @ContractNO is null
            begin
              select @Status=4, @Msg='分店'+@StoreNO+'，母商品ID'+convert(varchar, @ParentID)+'库存不足，并且无法获取默认进价。'
              print @Msg
              return
            end

          -- 看看有没有一样的批次，如果有，更新，没有，插入新批次
          select @NewBatchID=null
          select @NewBatchID=nBatchID from tStockBatch where sStoreNO=@StoreNO and nGoodsID=@ParentID and sBatchTypeID='8'
                                                             and nBatchPrice=@BatchPrice and nVendorID = @VendorID and sContractNO = @ContractNO
                                                             and nActionQty+nLockedQty-nPendingQty<=0 and ( @IsSale = 0
                                                                                                            or (sInspectNO=convert(varchar, @GoodsID) and nRatio=@Ratio)
                                                             )

          if @NewBatchID is not null
            begin
              update tStockBatch set nBatchQty=nBatchQty-@ParentQty, nPendingQty=nPendingQty+@ParentQty, nAmount=isnull(nAmount,0)-@SaleAmount,
                sDeclarationNO=convert(varchar, convert(numeric(12,3), sDeclarationNO)-@Qty)
              where sStoreNO=@StoreNO and nBatchID=@NewBatchID
            end
          else
            begin
              /* 插入负批次 */
              exec up_GetBatchID @StoreNO, @NewBatchID output /* 取批次号*/
              select @err=@err+@@error

              select @o='ci='+Convert(varchar, @ci)+' && 插入负库存，ParentID=' +convert(varchar, @ParentID)+',BatchID='+convert(varchar, @NewBatchID)
                        +',Qty='+convert(varchar, @Qty)+',ParentQty='+convert(varchar, @ParentQty)
              print @o

              -- 销售产生的，用sInspectNO和sDeclarationNO保存子商品ID和数量
              insert into tStockBatch(sStoreNO, nBatchID, nGoodsID, nVendorID, sBatchTypeID, sBatchType,
                                      nBatchQty, nBatchPrice, nActionQty, nLockedQty, nPendingQty, nPendingPrice, dBatchDate,
                                      dLastDownTime, nBuyTaxPct, sRecNO, nAmount, dLastUpdateTime, sTradeModeID, sContractNO, nRatio,
                                      sInspectNO, sDeclarationNO)
              values(@StoreNO, @NewBatchID, @ParentID, @VendorID, '8', '亏损',
                               -@ParentQty, @BatchPrice, 0, 0, @ParentQty, @BatchPrice, @rq,
                                                                           getdate(), @Tax, isnull(@PaperNO, CONVERT(varchar, getdate(), 112)), -@SaleAmount, getdate(), @TradeModeID, @ContractNO, iif(@IsSale=1, @Ratio, null),
                     iif(@IsSale=1, convert(varchar, @GoodsID), null), iif(@IsSale=1, convert(varchar, -@Qty), null))
              select @err=@err+@@error

            end

          insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                     sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
          values(@StoreNO, @NewBatchID, dbo.fn_BatchLogSerID(@StoreNO, @NewBatchID), @ParentID, @VendorID, '8',
                           '亏损', @Qty, @BatchPrice, @rq, -1, isnull(@PaperNO, CONVERT(varchar, getdate(), 112)), @Tax)
          select @err=@err+@@error

          insert into rj_DealBatch(dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                                   nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                                   sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO,
                                   sLocatorNO, sInspectNO )
          values( @rq, @TmpID, 1, @NewBatchID, '8', @ParentID,
                       null, @VendorID, -@ParentQty, -@SaleAmount, null, @BatchPrice,
                  @StoreNO, GETDATE(), @ContractNO, @TradeModeID, @Tax, '母商品负',
                  null, @PaperNO )
          select @err=@err+@@error

          select @CQty = @ParentQty, @ParentQty=0, @ThisQty=@Qty, @Qty=0, @ThisPrice=round(@BatchPrice/@Ratio, 4),
                 @ThisSaleAmount=@SaleAmount, @SaleAmount=0, @BatchTypeID='5'

          select @BatchID=@NewBatchID, @ActionQty = @ParentQty
        end  -- 01AA end

      else  -- 这是还有批次的
        begin  -- 01BB begin
          select @ParentID = nParentID, @BatchTypeID=sBatchTypeID, @BatchID=nBatchID, @ActionQty = nActionQty, @BatchPrice=nBatchPrice, @VendorID=nVendorID,
                 @ContractNO=sContractNO, @TradeModeID=sTradeModeID, @Tax=nTaxPct, @Ratio = nRatio
          from @csp where nID=@ci

          select @ParentQty = round(@Qty/@Ratio, 3)

          select @o='ci='+Convert(varchar, @ci)+' && 获取母批次，ParentID='+convert(varchar, @ParentID)+',BatchID='+convert(varchar, @BatchID)+
                    ',Qty='+convert(varchar, @Qty)+',ParentQty='+convert(varchar, @ParentQty) + ',Ratio='+convert(varchar, @Ratio)
          print @o

          -- 判断一下批次够不够扣
          if @ActionQty >= @ParentQty
            select @CQty = @ParentQty, @ParentQty=0, @ThisQty=@Qty, @Qty=0, @ThisPrice=round(@BatchPrice/@Ratio, 4),
                   @ThisSaleAmount=@SaleAmount, @SaleAmount=0
          else
            select @CQty = @ActionQty, @ParentQty=@ParentQty-@ActionQty, @ThisQty=round(@CQty*@Ratio, 3), @Qty=@Qty-@ThisQty,
                   @ThisPrice=round(@BatchPrice/@Ratio, 4), @ThisSaleAmount=round(@AvgSalePrice*@ThisQty,2), @SaleAmount=@SaleAmount-@ThisSaleAmount

          -- 扣减原批次
          update tStockBatch set nActionQty=nActionQty - @CQty, dLastUpdateTime=getdate(), dLastDownTime=getdate()
          where sStoreNO = @StoreNO and nBatchID=@BatchID
          select @err=@err+@@error

          insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                     sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
          values(@StoreNO, @BatchID, dbo.fn_BatchLogSerID(@StoreNO, @BatchID), @ParentID, @VendorID, '8',
                           '亏损', @CQty, @BatchPrice, @rq, -1, isnull(@PaperNO, CONVERT(varchar, getdate(), 112)), @Tax)
          select @err=@err+@@error

          insert into rj_DealBatch(dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                                   nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                                   sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO,
                                   sLocatorNO, sInspectNO )
          values( @rq, @TmpID, 1, @BatchID, '8', @ParentID,
                       null, @VendorID, -@CQty, -@ThisSaleAmount, null, @BatchPrice,
                  @StoreNO, GETDATE(), @ContractNO, @TradeModeID, @Tax, '母商品负',
                  null, @PaperNO )
          select @err=@err+@@error

        end  -- 01BB end

      -- 计算新批次的数量，价格
      select @NewBatchID=null
      select @NewBatchID = nBatchID from tStockBatch where sStoreNO=@StoreNO and nGoodsID=@GoodsID and nVendorID=@VendorID
                                                           and sContractNO=@ContractNO and nBatchPrice=@ThisPrice and nActionQty>=0 and nPendingQty=0 and nLockedQty=0

      if @NewBatchID is not null
        begin  -- 有相同批次，加数量上去
          select @o='顺序='+convert(varchar, @ci)+',增加现有批次,ParentID='+convert(varchar, @ParentID)+',ThisQty='+convert(varchar, @ThisQty)+',CQty='+convert(varchar, @CQty)
                    +',LeftParentQty='+convert(varchar, @ParentQty)
          print @o
          update tStockBatch set nActionQty=nActionQty+@ThisQty where sStoreNO=@StoreNO and nBatchID=@NewBatchID
          select @err=@err+@@error
        end
      else  -- 没有相同批次，增加新批次
        begin  -- 01CC begin
          exec up_GetBatchID @StoreNO, @NewBatchID out
          select @o='顺序='+convert(varchar, @ci)+',新增溢余批次,ParentID='+convert(varchar, @ParentID)+',ThisQty='+convert(varchar, @ThisQty)+',CQty='+convert(varchar, @CQty)
                    +',LeftParentQty='+convert(varchar, @ParentQty)
          print @o
          insert into tStockBatch(sStoreNO, nBatchID, nGoodsID, nVendorID, sBatchTypeID, sBatchType,
                                  nBatchQty, nBatchPrice, nActionQty, nLockedQty, nPendingQty, nPendingPrice, dBatchDate,
                                  dLastDownTime, nBuyTaxPct, sRecNO,
                                  nAmount, dLastUpdateTime, sTradeModeID, sContractNO, nRatio)
          values(@StoreNO, @NewBatchID, @GoodsID, @VendorID, '5', '溢余',
                           @ThisQty, @ThisPrice, @ThisQty, 0, 0, @ThisPrice, @rq,
                                                                 getdate(), @Tax, isnull(@PaperNO, CONVERT(varchar, getdate(), 112)),
                                                                 null, getdate(), @TradeModeID, @ContractNO, null)
          select @err=@err+@@error
        end  -- 01CC end

      insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                 sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
      values(@StoreNO, @NewBatchID, dbo.fn_BatchLogSerID(@StoreNO, @NewBatchID), @GoodsID, @VendorID, '5',
                       '溢余', @ThisQty, @ThisPrice, @rq, 1, isnull(@PaperNO, CONVERT(varchar, getdate(), 112)), @Tax)
      select @err=@err+@@error

      insert into rj_DealBatch(dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                               nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                               sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO,
                               sLocatorNO, sInspectNO )
      values( @rq, @TmpID, 1, @BatchID, '5', @GoodsID,
                   null, @VendorID, @ThisQty, @ThisSaleAmount, null, @ThisPrice,
              @StoreNO, GETDATE(), @ContractNO, @TradeModeID, @Tax, '子商品正',
              null, @PaperNO )
      select @err=@err+@@error

      -- 写子母商品转换日志
      insert into tFreshSplitRec(dTradeDate,sStoreNO,nGoodsID,nParentID,nBatchID,nVendorID,sContarctNO,sTradeModeID,nQty,
                                 nParentQty,nBatchPrice,nParentPrice,nRatio,sPaperNO,sMemo,nSaleAmount,nTmpBatchID,dLastUpdateTime)
      values(getdate(), @StoreNO, @GoodsID, @ParentID, @BatchID, @VendorID, @ContractNO, @TradeModeID, @ThisQty,
                        @CQty, @ThisPrice, @BatchPrice, @Ratio, @PaperNO, null, @ThisSaleAmount, @TmpID, getdate())
      select @err=@err+@@error

      -- 记录最后成本价
      if @BatchTypeID<>'5'
        begin
          if exists(select 1 from tStoreGoodsOtherInfo where sStoreNO=@StoreNO and nGoodsID = @GoodsID and sTypeID='LastCost')
            update tStoreGoodsOtherInfo set nVendorID=@VendorID, sContractNO=@ContractNO, nValue1=@ThisPrice, nValue2=@Tax,
              nValue3=@ParentID, sValue1=@TradeModeID, dLastUpdateTime=getdate()
            where sStoreNO=@StoreNO and nGoodsID = @GoodsID and sTypeID='LastCost'
          else
            insert into tStoreGoodsOtherInfo(sStoreNO,nGoodsID,sTypeID,sType,nVendorID,sContractNO,sMemo,sValue1,sValue2,sValue3,nValue1,nValue2,nValue3,dLastUpdateTime)
            values(@StoreNO,@GoodsID,'LastCost','最后成本价',@VendorID,@ContractNO,null,@TradeModeID,null, null,@ThisPrice,@Tax,@ParentID,getdate())
          select @err=@err+@@error
        end

      select @Amount=isnull(@Amount,0)+round(@CQty*@BatchPrice,2)

      select @ci=@ci+1

    end  -- 01 end


  if @err<>0
    begin
      rollback transaction
      select @Status=3, @Msg='分割失败'
      print @Msg
      return
    end
  else
    begin
      commit transaction
      select @Status=0, @Msg='分割成功'
    end

end