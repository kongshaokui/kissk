ALTER PROCEDURE [dbo].[rj_ComArticlePosCost]
  @rq [datetime] = null
AS
begin
  /*******************************************************
  把tPosSaleCost中的组合商品成分的成本汇总更新回组合商品
  *******************************************************/
  if @rq is null select @rq=convert(varchar, getdate(), 111)
  select dTradeDate, sStoreNO, sPosNO, nSerID, a.nItem, b.nGoodsID,
      nSaleCost=sum(nSaleCost), nVendorID=case when min(sContractNO)=max(sContractNO) then min(nVendorID) else 0 end,
      sContractNO=case when min(sContractNO)=max(sContractNO) then min(sContractNO) else '' end
  into #pc
  from tPosSaleCost as a, tComplexElement as b
  where a.dLastUpdateTime>=@rq and a.sMemo='组合成分' and a.nGoodsID = b.nElementID
  group by dTradeDate, sStoreNO, sPosNO, nSerID, a.nItem, b.nGoodsID

  update tPosSaleCost set nSaleCost=b.nSaleCost, nVendorID=b.nVendorID, sContractNO=b.sContractNO, dLastUpdateTime=getdate(),
    nRatio = 99.99
  from tPosSaleCost as a, #pc as b
  where a.dTradeDate=b.dTradeDate and a.sStoreNO=b.sStoreNO and a.sPosNO=b.sPosNO and a.nSerID=b.nSerID
        and a.nGoodsID=b.nGoodsID and a.nItem=b.nItem and a.nSaleCost=0 and not (isnull(a.nRatio,0)=99.99)

end