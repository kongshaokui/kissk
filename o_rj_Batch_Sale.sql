ALTER procedure [dbo].[rj_Batch_Sale]
  @StoreNO [varchar](20),
  @rq [datetime]
as
begin
  /*
  日结批次处理--销售
  版本：4.0 SQL
  1.1 修改：tStockBatch增加字段sTradeModeID用于记录交易方式。优先扣减购销批次。
  -------------------------------------------------------------
  2.0 修改
  增加多店支持，增加批次的经营方式、合同号
  调整部分算法
  ------------------------------------------------------------
  2.1 修改 2013-05-29
  销售批次改成逐条小票明细处理，处理结果放到tPosSaleCost表
  ------------------------------------------------------------
  2.2 修改  2013-07-12
  增加参数配置是否低价优先
  ----------------------------------------------------------
  2.3 修改 2013-7-22
  rj_TmpBatch增加nLeftQty的索引，里面条件由<>0改成<0，应该可以加快批次处理速度
  ----------------------------------------------------------
  2.4 修改 2014-01-17
  增加参数配置处理优先顺序，参数tSystemCtrl sCode='BatchSalePiority'，配置例子为'132'，含义：1购销代销3先进先出2价格
  ------------------------------------------------------------
  2.5 修改 2014-01-25
  如果取不到供应商，商品的税率从tGoods取，还是没有的话，用17税
  ---------------------------------------------------------
  2.5 SQL 修改 2014-04-01
  不知道为什么sql server中，这类过程只要有两个begin tran和commit tran，都容易报错。
  改成一个tran
  ---------------------------------------------------------
  2.6 SQL 修改 2014-04-02
  插入tStockBatch的时候，小票号应该用@PosSerID，原来用错了@SerID
  --------------------------------------------------------
  2.7 SQL 修改
  增加BOM商品的处理，如果没有有效库存，则先进行加工再扣减销售批次
  ---------------------------------------------------------------
  2.8 SQL 修改
  BOM处理增加参数，是不是在过程中进行加工（如果过程不处理，就是晚上日结再统一加工）
  ---------------------------------------------------------------
  2.9 SQL 修改
  代营商品的扣点，原来是从批次，改取tStoreGoodsVendor.nRealRatio
  ------------------------------------------------------------
  3.0 SQL 修改 2016-03-04
  还是代营商品的，有些客户不做进货（不进货还做什么代营？？？？），没批次的情况下，取的就是默认扣点，然后后来进货又重新计算成本调整，一塌糊涂
  改成如下规则：
  1. 没批次的，如果取到的默认供应商是代营，那么使用nRealRatio而不是nRatio
  2. 代营的商品负批次重新进货冲减的，如果是同一合同，不再计算成本冲减
  3. 顺便把没批次的时候取默认供应商进价的，改成使用过程了
  ------------------------------------------------------------
  3.2 SQL 修改 2017-07-12
  把生鲜分割、组合商品、库存处理，干脆都集合进来了，过程会变得超复杂，但是其他流程处理的就会方便些
  组合商品的处理比较麻烦，所以另外弄了个过程，把销售拆好另外放入rj_TmpBatch，处理完之后再更新回去
  把更新库存的功能加上
  ------------------------------------------------------------
  3.3 SQL 修改 2018-01-02
  生鲜分割的有个bug，在来源是负库存的情况下，会算错销售（算到来源了），修正。
  生鲜分割的，发现有分割商品和分割来源是不同结算方式的（分割购销、来源联营），
  这个除了在基础资料上进行限制之外，
  这里的处理也加上判断，出现这种情况，按照分割商品的合同及结算方式处理
  ------------------------------------------------------------
  3.4 SQL 修改 2018-04-21
  生鲜分割商品的历史负批次处理，如果是母商品没批次，而这个又不生成新的负批次，最后更新库存，如果母商品会报错，就不更新了
  ------------------------------------------------------------
  3.5 SQL 修改 2018-06-27
  生鲜分割的，当母商品没有库存的时候，算的子商品的数量、价格都不对，修正
  --------------------
  3.6 修改 2018-09-16
  分割商品、来源，其中有一个没有tStoreGoods或者tStoreGoodsVendor记录的，就不管了
  --------------------
  3.7 修改 2018-11-21
  有些情况下分割商品的成本写入tPosSaleCost有问题，修正
  --------------------
  3.8 修改 2018-12-16
  分割品采用BOM的方式处理
  --------------------
  3.9 修改 2019-05-29
  增加参数，NegBatchIgnoreAdj，如果为1，那么在冲减销售负库存的时候，盈余的批次，不计算成本冲减
  配送不允许负库存
  --------------------
  4.0 修改 2019-10-20
  增加双成本支持
  ------------------------------------------------------------
  基本处理流程：
  begin
  |
  取待处理销售批次
  |
  查找商品对应的有效批次
  |
  如果销售数量不为，并且找到有效批次
    begin
      |
      计算本次可扣减数量(如果可用量小于销售量，则为可用量，否则销售量)
      |
      更新批次，更新剩余未扣减销售量
      |
    end
  |
  如果剩余销售数量不为
    begin
      |
      取商品的暂置供应商、暂置成本价
      |
      查找相同供应商、成本价的暂置批次
      |
      如果找到暂置批次，增加暂时批次的待处理数量
      |
      如果找不到暂置批次，新增暂置批次
    end
  |
  end
  商品发生销售、找不到可用批次扣减时，将置为暂置批次。暂置批次对应的供应商、成本价的获取顺序
  1. 主供应商及其的默认进价。
  2. 任何一个供应商及其默认进价。
  3. '999999'，库存平均价
  4. '999999'，商品售价
  */
  declare @TmpID numeric(12),  /* 待处理批次的ID号，对应rj_TmpBatch.ID */
  @DealDate datetime,  /* 处理日期*/
  @OldBatchID numeric(16),  /* 要处理的旧销售批次的批次号*/
  @GoodsID numeric(8),  /* 商品编码*/
  @OldVendorID numeric(8),  /* 要处理的旧销售批次的供应商编码*/
  @Qty numeric(14,3),  /* 要处理的销售数量*/
  @SaleAmount numeric(14,2),  /* 要处理的销售金额*/
  @CQty numeric(14,3),  /* 本批次可扣减数量*/
  @CAmt numeric(14,2),  /* 本批次可扣减数量对应的销售金额*/
  @OldBatchPrice numeric(14,4),  /* 要处理的旧销售批次的批次价*/
  @OldBatchPrice2 numeric(14,4),  /* 要处理的旧销售批次的批次价2 */
  @BatchDate datetime,  /* 要处理的旧销售批次的批次日期*/
  @NewBatchID numeric(16),  /* 可用批次的批次号*/
  @NewVendorID numeric(8),  /* 可用批次的供应商编码*/
  @ActionQty numeric(14,3),  /* 可用批次数量*/
  @NewBatchPrice numeric(14,4),   /* 可用批次的批次价*/
  @NewBatchPrice2 numeric(14,4),   /* 可用批次的批次价2*/
  @BatchTypeID varchar(3),  /*  批次类型标志*/
  @BatchType varchar(20), /* 批次类型*/
  @Tax numeric(6,4),  /* 税率*/
  @o varchar(80),  /* 用于检测输出*/
  @err int,  /* 用于错误处理*/
  @SerID numeric(8),  /* tStockBatchLog 的顺序号*/
  @TradeModeID varchar(10),  /* 交易方式*/
  @SalePrice numeric(12,2),
  @ContractNO varchar(20),
  @Ratio numeric(6,4),
  @TmpContractNO varchar(20),
  @BusinessTypeID varchar(2),
  @TradeDate datetime, @PosNO varchar(3), @PosSerID numeric(4), @PosItem numeric(3), @PosSort int,
  @PosSalePrice numeric(12,2), @DisAmount numeric(12,2), @CDis numeric(12,2), @SalesClerkNO varchar(20), @CategoryNO varchar(8), @CategoryID numeric(8),
  @CardNO varchar(20),
  @LowPriceFirst int,
  @GType varchar(8),
  @IsFreshSplit int, /* 是否生鲜分割 */ @ParentID numeric(8),  /* 母商品的ID */
  @RQty numeric(12,3), @RealBatchPrice numeric(16,4), @Option varchar(40),
  @PosUpdateStock int = 0, @StockQty numeric(12,3), @StockAmount numeric(16,2),
  @LocatorNO varchar(20), @NegBatchIgnoreAdj int, @BatchTypeID1 varchar(10), @StoreTypeID varchar(4)

  /* 版本 3.2 增加，先处理组合商品，另用一个过程了 */
  exec rj_Batch_ComArticleSplit @rq
  if @@error<>0 return

  if exists(select 1 from tSystemCtrl where sCode='PosUpdateStock' and sValue1='1' ) select @PosUpdateStock = 1

  declare @TmpAmount numeric(12,2),
  @TmpStatus smallint,
  @TmpMsg varchar(200),
  @ExecStatus int,
  @TmpQty numeric(12,3),
  @PaperNO varchar(16)

  select @err=0
  select  @BatchType=sComDesc from tCommon where sLangID='936' and sCommonNO='BATT' and sComID='3'
  select @BusinessTypeID = sValue1 from tSystemCtrl where sCode='BusinessTypeID'

  if exists(select 1 from tSystemCtrl where sCode='NegBatchIgnoreAdj' and sValue1='1')
    select @NegBatchIgnoreAdj=1
  else select @NegBatchIgnoreAdj=0

  declare @pi1 varchar(1), @pi2 varchar(1) ,@pi3 varchar(1), @pi varchar(20)
  declare @Pior1 varchar(40), @Pior2 varchar(40) ,@Pior3 varchar(40)
  select @pi=sValue1 from tSystemCtrl where sCode='BatchSalePiority'
  if isnull(@pi,'') not in ('123', '132', '213','231','312','321') select @pi='123'
  select @pi1=substring(@pi, 1, 1), @pi2=substring(@pi, 2, 1), @pi3=substring(@pi, 3, 1)

  /* 游标取待处理销售*/
  declare cdeal cursor for select ID, dDealDate, nBatchID, nGoodsID, nVendorID, -nLeftQty,
                             -nLeftAmount, nBatchPrice, sBatchTypeID, dBatchDate, sStoreNO, sContractNO, nFGoodsID=nGoodsID,
                                                                                                         dTradeDate=dBatchDate, sPosNO=substring(sPaperNO, 1, 3), nSerID=convert(numeric(4), substring(sPaperNO,4,4)),
                                                                                                         nItem=convert(numeric(3), substring(sPaperNO,8,3)), sOption, sPaperNO, sLocatorNO, nBatchPrice2
                           from rj_TmpBatch where dDealDate=@rq and sBatchTypeID='3' and nLeftQty<0
                           order by ID
  open cdeal
  fetch cdeal into @TmpID, @DealDate, @OldBatchID, @GoodsID, @OldVendorID, @Qty,
    @SaleAmount, @OldBatchPrice, @BatchTypeID, @BatchDate, @StoreNO, @TmpContractNO, @GoodsID,
    @TradeDate, @PosNO, @PosSerID, @PosItem, @Option, @PaperNO, @LocatorNO, @OldBatchPrice2
  while @@fetch_status=0
    begin
      /* 店号 */
      if isnull(@StoreNO,'')=''
        begin
          raiserror ('店号为空，请检查！' , 16, 1)
          return
        end

      select @StoreTypeID=sStoreTypeID from tStore where sStoreNO=@StoreNO
      if @StoreTypeID='3' and isnull(@LocatorNO,'')=''
        begin
          select @o='rj_TmpBatch.ID='+convert(varchar, @TmpID)+', 配送商品ID='+convert(varchar, @GoodsID)+', 没有指定储位号'
          raiserror (@o , 16, 1)
          return
        end

      select @GType = sGoodTypeID, @IsFreshSplit = case when nTag&2048=2048 then 1 else 0 end from tGoods where nGoodsID=@GoodsID

      /* 生鲜分割完整性判断 */
      if @IsFreshSplit = 1 select @IsFreshSplit = dbo.fn_IsFreshSplitDataOK(@StoreNO, @GoodsID)

      /* 小票的信息，这个很烦，只能从小票里面现取了 */
      select @PosSalePrice=null, @DisAmount=null, @SalesClerkNO=null, @CategoryNO=null, @CategoryID=null
      select @PosSalePrice=round(nSalePrice,2), @DisAmount=nDisAmount, @SalesClerkNO=sSalesClerkNO from tPosSaleDtl
      where dTradeDate=@TradeDate and sStoreNO=@StoreNO and sPosNO=@PosNO and nSerID=@PosSerID and nItem=@PosItem
      select @CardNO=sCardNO from tPosSale
      where dTradeDate=@TradeDate and sStoreNO=@StoreNO and sPosNO=@PosNO and nSerID=@PosSerID

      /* 分类或者柜组 */
      if @BusinessTypeID='E'
        select @CategoryNO=sOrgNO from tStoreGoodsOrg where sStoreNO=@StoreNO and nGoodsID=@GoodsID
      else
        begin
          select @CategoryID=nCategoryID from tGoods where nGoodsID=@GoodsID
          select @CategoryNO = sCategoryNO from tCategory where nCategoryID=@CategoryID
        end

      begin transaction  /* 事务控制，每条记录独立一个事务*/

      /* 先判断一下，如果是原料是BOM，而且没有足够批次，那么先加工一下，暂时不考虑加工过程中批次有变化的情况 */
      if exists(select 1 from tSystemCtrl where sCode='SaleBatchBom' and sValue1='1')
        begin  /* BOM1 begin */
          select @GType=sGoodTypeID from tGoods where nGoodsID=@GoodsID
          if @GType = 'BOM'
            begin  /* 0100 begin */
              select @TmpQty=sum(nActionQty) from tStockBatch where sStoreNO=@StoreNO and nGoodsID=@GoodsID and nActionQty>0
              select @PaperNO = 'POS'+isnull(@PosNO+substring(convert(varchar,10000+@PosSerID),2,4) + substring(convert(varchar, 1000+@PosItem),2,3),'')

              select @TmpQty = @Qty - isnull(@TmpQty ,0)
              if @TmpQty > 0
                begin  /* 0100aa begin */
                  exec @ExecStatus=rj_Batch_MakeBOM @StoreNO, @GoodsID, @TmpQty, @PaperNO, @TmpStatus out, @TmpMsg out, @TmpAmount out
                  if @ExecStatus<>0 or @TmpStatus<>0
                    begin
                      deallocate cdeal
                      rollback transaction
                      rollback transaction
                      select @TmpMsg = 'BOM商品ID -- '+convert(varchar,@GoodsID) + '加工出错。' + @TmpMsg
                      print @TmpMsg
                      raiserror(@TmpMsg, 16, @TmpStatus)
                      return
                    end
                end   /* 0100aa end */
            end     /* 0100 end */
        end  /* BOM1 end */

      -- 版本3.8，生鲜分割，也按照BOM的方式处理，不够了，先用来源分割
      if @IsFreshSplit=1
        begin  /* 01AA begin */
          select @TmpQty=sum(nActionQty) from tStockBatch where sStoreNO=@StoreNO and nGoodsID=@GoodsID and nActionQty>0

          select @TmpQty = @Qty - isnull(@TmpQty ,0)
          if @TmpQty > 0
            begin  /* 01AA01 begin */
              -- 计算一下，需要加工的数量，对应的销售金额是多少
              select @CAmt = round(@SaleAmount/@Qty*@TmpQty,2)
              exec @ExecStatus = rj_Batch_MakeSplit @rq, @StoreNO, @GoodsID, @TmpQty, @PaperNO, @TmpID, @CAmt, @TmpStatus out, @TmpMsg out
              if @ExecStatus<>0 or @TmpStatus<>0
                begin
                  close cdeal
                  deallocate cdeal
                  rollback transaction
                  select @TmpMsg = '分割商品ID -- '+convert(varchar,@GoodsID) + '分割出错。' + @TmpMsg
                  print @TmpMsg
                  raiserror(@TmpMsg, 16, @TmpStatus)
                  return
                end
            end   /* 01AA01 end */
        end     /* 01AA end */

      /* 游标取可用批次*/
      declare cbatch cursor for select sPior1=convert(varchar(40), case @pi1 when '1' then case sTradeModeID when '1' then '1' when '4' then '2' when '6' then '3' else '4' end
                                                                   when '2' then convert(varchar, 1000000000000+nBatchPrice)
                                                                   when '3' then convert(varchar, isnull(dProduceDate, dBatchDate), 112) + convert(varchar, nBatchID) end),
                                       sPior2=convert(varchar(40), case @pi2 when '1' then case sTradeModeID when '1' then '1' when '4' then '2' when '6' then '3' else '4' end
                                                                   when '2' then convert(varchar, 1000000000000+nBatchPrice)
                                                                   when '3' then convert(varchar, isnull(dProduceDate, dBatchDate), 112) + convert(varchar, nBatchID) end),
                                       sPior3=convert(varchar(40), case @pi3 when '1' then case sTradeModeID when '1' then '1' when '4' then '2' when '6' then '3' else '4' end
                                                                   when '2' then convert(varchar, 1000000000000+nBatchPrice)
                                                                   when '3' then convert(varchar, isnull(dProduceDate, dBatchDate), 112) + convert(varchar, nBatchID) end),
                                  nBatchID, nVendorID, nActionQty, nBatchPrice, sContractNO, sTradeModeID, nBuyTaxPct, nRatio, sBatchTypeID, nBatchPrice2
                                from tStockBatch where sStoreNO=@StoreNO and nGoodsID=@GoodsID and nActionQty>0
                                                       and (ISNULL(sLocatorNO,'')=isnull(@LocatorNO, '') or isnull(@LocatorNO, '') = '')
                                order by 1, 2, 3
      open cbatch
      fetch cbatch into @Pior1, @Pior2, @Pior3, @NewBatchID, @NewVendorID, @ActionQty, @NewBatchPrice, @ContractNO, @TradeModeID,
        @Tax, @Ratio, @BatchTypeID1, @NewBatchPrice2
      while @@fetch_status=0 and @Qty>0
        begin    -- 001
          if @ActionQty >= @Qty /* 批次可用数量>=要处理数量，可用批次扣减处理数量，待处理数量清为0 */
            select @CQty = @Qty, @RQty = @Qty, @CAmt = @SaleAmount
          else  /* 批次可用数量<要处理数量，可用批次清0，待处理数量减去批次数量 */
            select @CQty= @ActionQty, @RQty = @ActionQty, @CAmt = round(@SaleAmount/@Qty*@ActionQty,2)

          select @o='获取到批次 && BatchID='+convert(varchar, @NewBatchID)+',ActionQty='+convert(varchar, @ActionQty)+',CQty='+convert(varchar, @CQty)
                    + ',Qty='+convert(varchar, @Qty)
          print @o

          /* 处理合同号 */
          if @ContractNO is null
            select @ContractNO = sContractNO from tStoreGoodsVendor where sStoreNO=@StoreNO and nGoodsID=@GoodsID and nVendorID=@NewVendorID

          /* 取交易方式*/
          if @TradeModeID is null
            select @TradeModeID = sTradeModeID from tContract where sContractNO = @ContractNO
          if @TradeModeID is null
            select @TradeModeID=sTradeModeID from tStoreGoodsVendor where sStoreNO=@StoreNO and nGoodsID=@GoodsID and nVendorID=@NewVendorID
          if @TradeModeID is null select @TradeModeID='1'

          /* 代营的处理*/  /* 版本2.9 改成从tStoreGoodsVendor.nRealRatio */
          if @TradeModeID = '6'
            begin
              select @Ratio = nRealRatio*0.01 from tStoreGoodsVendor where sStoreNO=@StoreNO and nVendorID=@NewVendorID and nGoodsID=@GoodsID and sTradeModeID='6'
              select @NewBatchPrice = ROUND(@CAmt*(1-@Ratio)/@CQty,4)
            end

          /* 3.0 修改，代营的如果新旧合同一致，那么不作成本冲减差异计算 */
          -- 3.9 如果批次类型是溢余，并且设置了参数NegBatchIgnoreAdj，那么差异不算成本，而算成调整
          insert into rj_DealBatch(dDealDate, TmpID, nType,
                                   nBatchID, sBatchTypeID, nGoodsID,
                                   nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice,
                                   nRealBatchPrice,
                                   sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO,
                                   sLocatorNO, nBatchPrice2)
          values(@DealDate, @TmpID, case when @OldBatchID is not null then 3 else 1 end,
                            @NewBatchID, case when (@OldBatchID is not null and @BatchTypeID1='5' and @NegBatchIgnoreAdj=1) then '8' else @BatchTypeID end, @GoodsID,
                            @OldVendorID, @NewVendorID, -@RQty, -@CAmt, @OldBatchPrice,
                 case when (@TradeModeID='6' and @ContractNO=@TmpContractNO) then @OldBatchPrice else @NewBatchPrice end,
                 @StoreNO, GETDATE(), @ContractNO, @TradeModeID, @Tax, @TmpContractNO,
                 @LocatorNO, @NewBatchPrice2)
          select @err=@err+@@error

          /* 插入POS成本表，冲减的批次就先不管了 */
          if @OldBatchID is null
            begin
              select @PosSort=null
              select @PosSort=max(nSort)+1 from tPosSaleCost where dTradeDate=@TradeDate and sStoreNO=@StoreNO and sPosNO=@PosNO and nSerID=@PosSerID and nItem=@PosItem
              if @PosSort is null select @PosSort=1
              select @o='SaleAmount='+convert(varchar, @SaleAmount)+',CAmt='+convert(varchar, @CAmt)+',DisAmount='+convert(varchar, @DisAmount)
              print @o
              insert into tPosSaleCost(dTradeDate,sStoreNO,sPosNO,nSerID,nItem,nSort,
                                       nGoodsID,nSaleQty, nSalePrice, nSaleAmount,
                                       nDisAmount,
                                       sMemo,nSaleCost,nVendorID,sContractNO,nRatio,nTaxPct,sTradeModeID,dDailyDate,
                                       sSalesClerkNO,sCategoryNO,sCardNO,dLastUpdateTime, nSaleCost2)
              values(@TradeDate, @StoreNO, @PosNO, @PosSerID, @PosItem, @PosSort,
                                 @GoodsID, @RQty, @PosSalePrice, @CAmt,
                                 -- @DisAmount,
                                 case when @SaleAmount=0 then @DisAmount else round(@CAmt/@SaleAmount*@DisAmount,2) end,
                @Option, round(@RQty*@NewBatchPrice,2), @NewVendorID, @ContractNO, @Ratio, @Tax, @TradeModeID, @rq,
                @SalesClerkNO, @CategoryNO, @CardNO, getdate(), round(@RQty*@NewBatchPrice2,2))
              select @err=@err+@@error
            end

          update tStockBatch set nActionQty=nActionQty-@CQty, dLastDownTime =GETDATE(), dLastUpdateTime=GETDATE()
          where sStoreNO=@StoreNO and nBatchID=@NewBatchID
          select @err=@err+@@error

          /* 插入tStockBatchLog */
          insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                     sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
          values(@StoreNO, @NewBatchID, dbo.fn_BatchLogSerID(@StoreNO, @NewBatchID), @GoodsID, @NewVendorID, @BatchTypeID,
                           @BatchType, @CQty, @NewBatchPrice, @TradeDate, -1, isnull(@PaperNO,''), @Tax)
          select @err=@err+@@error

          -- 生鲜分割的，记录最后成本价
          if @IsFreshSplit = 1 and @BatchTypeID<>'5'
            begin
              if exists(select 1 from tStoreGoodsOtherInfo where sStoreNO=@StoreNO and nGoodsID = @GoodsID and sTypeID='LastCost')
                update tStoreGoodsOtherInfo set nVendorID=@NewVendorID, sContractNO=@ContractNO, nValue1=@NewBatchPrice, nValue2=@Tax,
                  nValue3=null, sValue1=@TradeModeID, dLastUpdateTime=getdate()
                where sStoreNO=@StoreNO and nGoodsID = @GoodsID and sTypeID='LastCost'
              else
                insert into tStoreGoodsOtherInfo(sStoreNO,nGoodsID,sTypeID,sType,nVendorID,sContractNO,sMemo,sValue1,sValue2,sValue3,nValue1,nValue2,nValue3,dLastUpdateTime)
                values(@StoreNO,@GoodsID,'LastCost','最后成本价',@NewVendorID,@ContractNO,null,@TradeModeID,null, null,@NewBatchPrice,@Tax,@ParentID,getdate())
              select @err=@err+@@error
            end

          update rj_TmpBatch set nLeftQty=nLeftQty-@RQty, nLeftAmount=nLeftAmount-@CAmt where ID=@TmpID  /* 处理数量清为*/
          select @err=@err+@@error
          /* 如果是以前的未处理批次，则更新未处理批次的剩余未处理数量 */
          if @OldBatchID is not null
            begin   -- 00101
              update tStockBatch set nBatchQty=nBatchQty+@CQty, nPendingQty=nPendingQty-@CQty, nAmount=nAmount+@CAmt,
                dLastDownTime =GETDATE(), dLastUpdateTime=GETDATE()
              where sStoreNO=@StoreNO and nBatchID=@OldBatchID
              select @err=@err+@@error
              /* 插入tStockBatchLog */
              insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                         sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
              values(@StoreNO, @OldBatchID, dbo.fn_BatchLogSerID(@StoreNO, @OldBatchID), @GoodsID, @OldVendorID, @BatchTypeID,
                               @BatchType, @CQty, @NewBatchPrice, @TradeDate, 1, isnull(@PaperNO,''), @Tax)
              select @err=@err+@@error
            end    -- 00101

          select @Qty=@Qty-@CQty, @DisAmount = @DisAmount - case when @SaleAmount=0 then @DisAmount else round(@CAmt/@SaleAmount*@DisAmount,2) end, @SaleAmount=@SaleAmount - @CAmt

          fetch cbatch into @Pior1, @Pior2, @Pior3, @NewBatchID, @NewVendorID, @ActionQty, @NewBatchPrice, @ContractNO, @TradeModeID,
            @Tax, @Ratio, @BatchTypeID1, @NewBatchPrice2
        end  -- 001
      close cbatch
      DEALLOCATE cbatch

      -- 分割品分割有问题，出错返回
      if @Qty>0 and @IsFreshSplit = 1
        begin
          close cdeal
          deallocate cdeal
          rollback transaction
          select @TmpMsg = 'TmpID='+convert(varchar, @TmpID)+'分割商品ID -- '+convert(varchar,@GoodsID) + '分割之后还是不够库存，请检查。'
                           +'LeftQty='+convert(varchar, @Qty)+ ', '+ @TmpMsg
          print @TmpMsg
          raiserror(@TmpMsg, 16, @TmpStatus)
          return
        end

      -- 配送的不能负批次
      if @StoreTypeID='3' and @Qty>0 and @OldBatchID is null
        begin
          close cdeal
          deallocate cdeal
          rollback transaction
          select @o='rj_TmpBatch.ID='+convert(varchar, @TmpID)+', 配送商品ID='+convert(varchar, @GoodsID)+', 储位号='+@LocatorNO+', 对应储位的批次库存不足以扣减'
          raiserror (@o , 16, 1)
          return
        end

      /* 如果有待处理数量没有扣减完增加负批次的数量、或者新增一个负批次*/
      if @Qty>0 and @OldBatchID is null
        begin  -- 02 begin
          select @NewVendorID=null, @NewBatchPrice=null, @Tax=null, @Ratio = null, @TradeModeID = null,  @ContractNO = null

          /* 取进价，从主供应商 版本3.0改成使用过程 */
          exec up_GetDefaultBuyPrice @GoodsID, @StoreNO, @ContractNO out, @NewVendorID out, @NewBatchPrice out, @TradeModeID out, @Tax out
          -- 加个处理，价格2清空
          select @NewBatchPrice2=null

          select @o='插入负批次 && Qty='+convert(varchar, @Qty)+',ContractNO='+@ContractNO+',Price='+convert(varchar, @NewBatchPrice)
          print @o

          /* 代营处理 */
          if @TradeModeID='6' and @NewBatchPrice>0 and @NewBatchPrice<1
            begin
              select @Ratio = @NewBatchPrice
              select @NewBatchPrice = ROUND(@SaleAmount*(1-@Ratio)/@Qty,4)
            end

          /* 查找相同类型供应商、商品、进价的负批次*/
          select @NewBatchID = null
          select top 1 @NewBatchID=nBatchID, @Tax=nBuyTaxPct from tStockBatch where sStoreNO=@StoreNO
                                                                                    and sBatchTypeID=@BatchTypeID
                                                                                    and nGoodsID=@GoodsID and nVendorID=@NewVendorID
                                                                                    and  sContractNO= @ContractNO and nBatchPrice=@NewBatchPrice and nActionQty+nLockedQty-nPendingQty<0
                                                                                    and nActionQty=0
          order by dBatchDate desc, nBatchID desc

          if @NewBatchID is not null /* 存在相同负批次，更改批次数量*/
            begin   -- 02AA begin
              insert into rj_DealBatch(dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                                       nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                                       sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO, nBatchPrice2)
              values(@DealDate, @TmpID, 1, @NewBatchID, @BatchTypeID, @GoodsID,
                                @OldVendorID, @NewVendorID, -@Qty, -@SaleAmount, @OldBatchPrice, @NewBatchPrice,
                     @StoreNO, GETDATE(), @ContractNO, @TradeModeID, @Tax, @ContractNO, null)
              select @err=@err+@@error

              /* 插入POS成本表，冲减的批次就先不管了 */
              if @OldBatchID is null
                begin  -- 02AA02 begin
                  select @PosSort=null
                  select @PosSort=max(nSort)+1 from tPosSaleCost where dTradeDate=@TradeDate and sStoreNO=@StoreNO and sPosNO=@PosNO and nSerID=@PosSerID and nItem=@PosItem
                  if @PosSort is null select @PosSort=1
                  insert into tPosSaleCost(dTradeDate,sStoreNO,sPosNO,nSerID,nItem,nSort,
                                           nGoodsID, nSaleQty,
                                           nSalePrice, nSaleAmount,nDisAmount,sMemo,nSaleCost,nVendorID,
                                           sContractNO,nRatio,nTaxPct,sTradeModeID,dDailyDate, sSalesClerkNO,sCategoryNO,sCardNO,dLastUpdateTime, nSaleCost2)
                  values(@TradeDate, @StoreNO, @PosNO, @PosSerID, @PosItem, @PosSort,
                                     @GoodsID, @Qty,
                                     @PosSalePrice, @SaleAmount, @DisAmount, @Option, round(@Qty*@NewBatchPrice,2), @NewVendorID,
                                                                             @ContractNO, @Ratio, @Tax, @TradeModeID, @rq, @SalesClerkNO, @CategoryNO, @CardNO, getdate(), null)
                  select @err=@err+@@error
                end   -- 02AA02 end

              update tStockBatch set nBatchQty=nBatchQty-@Qty, nPendingQty=nPendingQty+@Qty, nAmount=nAmount-@SaleAmount,
                dLastUpdateTime = GETDATE(), dLastDownTime = GETDATE()
              where sStoreNO=@StoreNO  and nBatchID=@NewBatchID
              select @err=@err+@@error
              /* 插入tStockBatchLog */
              insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                         sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
              values(@StoreNO, @NewBatchID, dbo.fn_BatchLogSerID(@StoreNO, @NewBatchID), @GoodsID, @NewVendorID, @BatchTypeID,
                               @BatchType, @Qty, @NewBatchPrice, @TradeDate, -1, isnull(@PaperNO,''), @Tax)
              select @err=@err+@@error

            end   -- 02AA end
          else /* 否则新增负批次*/
            begin    -- 02BB begin
              exec up_GetBatchID @StoreNO,  @NewBatchID output /* 取批次号*/
              insert into rj_DealBatch(dDealDate, TmpID, nType, nBatchID, sBatchTypeID, nGoodsID,
                                       nTmpVendorID, nRealVendorID, nQty, nAmount, nTmpBatchPrice, nRealBatchPrice,
                                       sStoreNO, dLastUpdateTime, sContractNO, sTradeModeID, nTaxPct, sTmpContractNO, nBatchPrice2)
              values(@DealDate, @TmpID, 0, @NewBatchID, @BatchTypeID, @GoodsID,
                                @OldVendorID,  @NewVendorID, -@Qty, -@SaleAmount, @OldBatchPrice, @NewBatchPrice,
                     @StoreNO, GETDATE(), @ContractNO, @TradeModeID, @Tax, @ContractNO, null)
              select @err=@err+@@error

              /* 插入POS成本表，冲减的批次就先不管了 */
              if @OldBatchID is null
                begin  -- 02BB02 begin
                  select @PosSort=null
                  select @PosSort=max(nSort)+1 from tPosSaleCost where dTradeDate=@TradeDate and sStoreNO=@StoreNO and sPosNO=@PosNO and nSerID=@PosSerID and nItem=@PosItem
                  if @PosSort is null select @PosSort=1

                  insert  into tPosSaleCost(dTradeDate,sStoreNO,sPosNO,nSerID,nItem,nSort,
                                            nGoodsID,nSaleQty,nSalePrice,
                                            nSaleAmount,nDisAmount,sMemo,nSaleCost,nVendorID,sContractNO,nRatio,nTaxPct,sTradeModeID,dDailyDate,
                                            sSalesClerkNO,sCategoryNO,sCardNO,dLastUpdateTime, nSaleCost2)
                  values(@TradeDate, @StoreNO, @PosNO, @PosSerID, @PosItem, @PosSort,
                                     @GoodsID, @Qty, @PosSalePrice,
                                     @SaleAmount, @DisAmount, @Option, round(@Qty*@NewBatchPrice,2), @NewVendorID, @ContractNO, @Ratio, @Tax, @TradeModeID, @rq,
                                                              @SalesClerkNO, @CategoryNO, @CardNO, getdate(), null)
                  select @err=@err+@@error
                end    -- 02BB02 end

              select @BatchType=sComDesc from tCommon where sLangID='936' and sCommonNO='BATT' and sComID=@BatchTypeID

              /* 插入负批次*/
              insert into tStockBatch(sStoreNO, nBatchID, nGoodsID, nVendorID,
                                      sBatchTypeID, sBatchType,
                                      nBatchQty, nBatchPrice, nActionQty, nLockedQty, nPendingQty, nPendingPrice, dBatchDate,
                                      dLastDownTime, nBuyTaxPct, sRecNO,
                                      nAmount, dLastUpdateTime, sTradeModeID, sContractNO, nRatio, nBatchPrice2)
              values(@StoreNO, @NewBatchID, @GoodsID, @NewVendorID,
                               @BatchTypeID, @BatchType,
                               -@Qty, @NewBatchPrice, 0, 0, @Qty, @NewBatchPrice, @TradeDate,
                                                                  getdate(), @Tax, isnull(@PaperNO,''),
                                                                  -@SaleAmount, getdate(), @TradeModeID, @ContractNO, @Ratio, null)
              select @err=@err+@@error
              /* 插入tStockBatchLog */
              insert into tStockBatchLog(sStoreNO, nBatchID, nSerID, nGoodsID, nVendorID, sBatchTypeID,
                                         sBatchType, nBatchQty, nBatchPrice, dBatchDate, nDirection, sRecNO, nBuyTaxPct)
              values(@StoreNO,  @NewBatchID, dbo.fn_BatchLogSerID(@StoreNO, @NewBatchID), @GoodsID, @NewVendorID, @BatchTypeID,
                                @BatchType, @Qty, @NewBatchPrice, @TradeDate, -1, isnull(@PaperNO,''), @Tax)
              select @err=@err+@@error
            end     -- 02BB end
        end    -- 02 end
      /* 待处理数量清零*/
      update rj_TmpBatch set nLeftQty=0, nLeftAmount=0 where ID=@TmpID
      select @err=@err+@@error
      select @Qty=0,  @SaleAmount=0

      /* 更新库存 */
      /* 3.4 需要增加判断，如果是生鲜分割，并且分割商品的旧批次，就不用做这步了 */
      if @PosUpdateStock = 0 and not (@IsFreshSplit = 1 and @OldBatchID is not null)
        begin
          select @StockQty = sum(nActionQty+nLockedQty-nPendingQty),
                 @StockAmount = sum(round((nActionQty+nLockedQty-nPendingQty)*nBatchPrice,2))
          from tStockBatch where sStoreNO = @StoreNO and nGoodsID = @GoodsID

          if @StockQty is not null
            update tStockAccount set nStockQty = @StockQty, nStockAmount = @StockAmount,
              nStockNetAmount = round(@StockAmount / isnull(@Tax, 1),2), nStockCost = round(@StockQty*nAvgCostPrice,2),
              nStockNetCost = round(@StockQty*nAvgCostPrice/isnull(@Tax, 1),2), dLastUpdateTime=getdate()
            where sStoreNO = @StoreNO and nGoodsID = @GoodsID
          select @err = @err+@@error
        end

      if @err=0 commit transaction
      else
        begin
          rollback transaction
          close cdeal
          DEALLOCATE cdeal
          return
        end

      fetch cdeal into @TmpID, @DealDate, @OldBatchID, @GoodsID, @OldVendorID, @Qty,
        @SaleAmount, @OldBatchPrice, @BatchTypeID, @BatchDate, @StoreNO, @TmpContractNO, @GoodsID,
        @TradeDate, @PosNO, @PosSerID, @PosItem, @Option, @PaperNO, @LocatorNO, @OldBatchPrice2

    end
  close cdeal
  DEALLOCATE cdeal

  /* 专门处理销售数量为0，销售金额不为的销售*/
  exec rj_Batch_ZeroSale @StoreNO, @rq

  /* tPosSaleCost中的组合商品的成分成本，更新回组合商品 */
  exec rj_ComArticlePosCost

end