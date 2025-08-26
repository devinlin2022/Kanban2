USE [MESDB_ARCH]
GO

/****** Object:  StoredProcedure [dbo].[OPERA_S_Rpt_Carton_Kanban]    Script Date: 2025/8/26 13:19:48 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
ALTER PROCEDURE [dbo].[OPERA_S_Rpt_Carton_Kanban]

(
@ent_id VARCHAR(MAX) = NULL,
@item_id VARCHAR(MAX) = NULL
)

AS

BEGIN

	-- SET NOCOUNT ON addped to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

-- declare table variable
DECLARE @data TABLE (
  Fillingline nvarchar(40) NULL,
  Category2 nvarchar(40) NULL,
  Color int NULL,
  FillingOrder nvarchar(40) NULL,
  FillingOrderQty float NULL,
  FillingProdQty float NULL,
  FillingSKU nvarchar(40) NULL,
  Cartonline nvarchar(40) NULL,
  CartonEntID int NULL,
  CartonCurShiftStartTimeLocal Datetime NULL,
  CartonSKU nvarchar(40) NULL,
  CartonOrder nvarchar(40) NULL,
  CartonProdQty float NULL,
  TubeStock float NULL,
  CartonStock float NULL,
  CaseStock float NULL,
  Shortage float NULL
);

INSERT INTO @data
select 
e1.ent_name Fillingline, 
max(util_reas.category2) Category2,
max(util_state.color) Color,
max(jef.cur_wo_id) FillingOrder,
COALESCE(max(jf.qty_reqd),0) FillingOrderQty, 
COALESCE(max(jf.qty_prod),0) FillingProdQty, 
max(wo.item_id) FillingSKU, 
max(case when ml.dispo = 'DCG' or jef.cur_wo_id is null then eg.ent_name else null end) Cartonline,
max(e2.ent_id) as CartonEntID,
max(e2.cur_shift_start_time_local) as CartonCurShiftStartTimeLocal,
max(case when ml.dispo = 'DCG' or jef.cur_wo_id is null then bi.item_id else null end) CartonSKU, 
max(case when ml.dispo = 'DCG' or jef.cur_wo_id is null then jej.wo_id else null end) CartonOrder, 
COALESCE(max(jej.qty_prod),0) CartonProdQty, 
--COALESCE(sum(ws.AVAIL_STCK),0) CartonStock,
COALESCE(sum(case when ml.dispo = 'DCT' or jef.cur_wo_id is null then ws.AVAIL_STCK else 0 end), 0) TubeStock,
COALESCE(sum(case when ml.dispo = 'DCG' or jef.cur_wo_id is null then ws.AVAIL_STCK else 0 end), 0) CartonStock,
COALESCE(sum(case when (ml.dispo = 'DCD' and i.item_desc like '%case%') or jef.cur_wo_id is null then ws.AVAIL_STCK else 0 end), 0) CaseStock,
(COALESCE(max(jf.qty_reqd),0)-COALESCE(max(jf.qty_prod),0)-COALESCE(max(jej.qty_prod),0)-COALESCE(sum(ws.AVAIL_STCK),0))as Shortage

from job_exec jef with (nolock)
inner join ent e1 with (nolock) on e1.ent_id = jef.ent_id and e1.ent_name like 'CNDCF[12]__'
inner join ent e2 with (nolock) on e2.parent_ent_id = e1.ent_id and e2.ent_name like '%Cartoner'

INNER JOIN util_exec WITH (nolock) ON util_exec.ent_id = jef.ent_id
INNER JOIN util_reas WITH (nolock) ON util_exec.cur_reas_cd = util_reas.reas_cd
INNER JOIN util_state WITH (nolock) ON util_exec.cur_state_cd = util_state.state_cd

left join job jf with (nolock) on jef.cur_wo_id = jf.wo_id and jf.init_sched_ent_id = e2.ent_id   --change e2 to e1 to catch the Line output
left join wo with (nolock) on wo.wo_id = jf.wo_id
left join bom_item bi with (nolock) on wo.bom_ver_id = bi.ver_id and wo.item_id = bi.parent_item_id
left join item i on bi.item_id = i.item_id
left join OPERA_MII_MATERIAL_LIST ml with (nolock) on ml.matnr = bi.item_id
left join OPERA_MII_WAREHOUSE_STOCK ws with (nolock) on ws.MATNR = bi.item_id and ws.STGE_BIN = 'FGSTAGING'
left join (select je.ent_id ent_id, je.cur_wo_id wo_id, j.qty_prod qty_prod, j.item_id item_id, j.job_desc job_desc
			from job_exec je with (nolock) inner join job j with (nolock) on je.cur_wo_id = j.wo_id where je.ent_id between 175 and 185 ) jej 
			on jej.item_id = bi.item_id and jej.job_desc like 'CNDCG%'
left join ent eg with (nolock) on jej.ent_id = eg.ent_id
where e1.ent_name like 'CNDCF%'-- and (ml.dispo = 'DCG' or jef.cur_wo_id is null)
and (jef.ent_id IN (select * from [dbo].[OPERA_fn_S_Split_List](@Ent_id)) OR @ent_id IS NULL)
and (bi.item_id like '%' + @item_id + '%' or @item_id is null)
group by e1.ent_name
order by e1.ent_name

select  Fillingline,
		Category2,
		Color,
		FillingOrder,
		COALESCE(ip.qty_prod,0) as Cur_qtyprod,
		FillingOrderQty,
		FillingProdQty,
		FillingSKU,
		Cartonline,
		CartonSKU,
		CartonOrder,
		CartonProdQty,
		CartonStock,
		Shortage
from @data d
left join (select wo_id, 
				shift_start_local, 
				ent_id, 
				sum(qty_prod) qty_prod 
				from item_prod
				where wo_id IN (select distinct FillingOrder from @data)
					and ent_id IN (select distinct CartonEntID from @data)
					and shift_start_local IN (select distinct CartonCurShiftStartTimeLocal from @data)
				group by wo_id, shift_start_local, ent_id) ip on ip.wo_id = FillingOrder and ip.ent_id = CartonEntID and ip.shift_start_local = CartonCurShiftStartTimeLocal

End
GO


