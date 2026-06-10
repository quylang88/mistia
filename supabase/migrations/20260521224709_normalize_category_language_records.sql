create temporary table mistia_category_localized_names (
  system_key text primary key,
  name_vi text not null,
  name_en text not null,
  name_ja text not null,
  sort_order integer not null
) on commit drop;

insert into mistia_category_localized_names (system_key, name_vi, name_en, name_ja, sort_order)
values
  ('parent_expense_food', 'Sinh hoạt', 'Essentials', '生活費', 0),
  ('parent_expense_cost_of_goods', 'Tiền hàng', 'Cost of goods', '仕入高', 1),
  ('parent_expense_home_bills', 'Nhà ở & hóa đơn', 'Housing & bills', '住居・請求', 2),
  ('parent_expense_family_children', 'Con cái', 'Children', '子ども', 3),
  ('parent_expense_transport_vehicle', 'Đi lại & xe cộ', 'Transport & vehicle', '交通・車', 4),
  ('parent_expense_personal_shopping', 'Mua sắm', 'Shopping', '買い物', 5),
  ('parent_expense_health', 'Sức khỏe', 'Health', '健康', 6),
  ('parent_expense_family_relations', 'Gia đình & quan hệ', 'Family & relationships', '家族・交際', 7),
  ('parent_expense_entertainment_social', 'Giải trí', 'Entertainment', '娯楽', 8),
  ('parent_expense_work_study', 'Học tập & công việc', 'Study & work', '学習・仕事', 9),
  ('parent_expense_financial_obligations', 'Tài chính & nghĩa vụ', 'Finance & obligations', '金融・支払い', 10),
  ('parent_expense_pet_care', 'Thú cưng', 'Pets', 'ペット', 11),
  ('parent_expense_uncategorized', 'Chi khác', 'Other expenses', 'その他支出', 12),
  ('parent_income_work', 'Lương & công việc', 'Salary & work', '給与・仕事', 13),
  ('parent_income_sales_other', 'Kinh doanh', 'Business', '事業', 14),
  ('parent_income_investment_return', 'Đầu tư & tài chính', 'Investment & finance', '投資・金融', 15),
  ('parent_income_refund_adjustment', 'Hoàn lại & bồi hoàn', 'Refunds & reimbursements', '返金・調整', 16),
  ('parent_income_support_gift', 'Hỗ trợ & trợ cấp', 'Support & benefits', '支援・手当', 17),
  ('parent_income_liquidation', 'Thanh lý', 'Liquidation', '売却', 18),
  ('parent_income_uncategorized', 'Thu khác', 'Other income', 'その他収入', 19),
  ('grocery', 'Đi chợ', 'Groceries', '食料品', 0),
  ('business_meals', 'Ăn uống công việc', 'Business meals', '会食', 1),
  ('cafe_tea', 'Cafe / trà sữa', 'Cafe / milk tea', 'カフェ・ミルクティー', 2),
  ('daily_supplies', 'Đồ tiêu dùng', 'Daily supplies', '日用品', 3),
  ('dine_out', 'Ăn ngoài', 'Dining out', '外食', 4),
  ('food_delivery', 'Đặt đồ ăn', 'Food delivery', 'フードデリバリー', 5),
  ('small_appliances', 'Đồ gia dụng nhỏ', 'Small home goods', '小型家電', 6),
  ('snacks', 'Ăn vặt / bánh kẹo', 'Snacks', 'おやつ', 7),
  ('goods_sourcing', 'Chi phí lấy hàng', 'Sourcing costs', '仕入れ費用', 0),
  ('import_goods', 'Nhập hàng', 'Inventory purchases', '仕入れ', 1),
  ('marketing_ads', 'Marketing / quảng cáo', 'Marketing / ads', 'マーケティング・広告', 2),
  ('packaging', 'Đóng gói / bao bì', 'Packaging', '梱包材', 3),
  ('platform_fee', 'Chi phí sàn', 'Platform fees', 'プラットフォーム手数料', 4),
  ('shipping_fee', 'Phí vận chuyển hàng', 'Shipping fees', '配送料', 5),
  ('other_sales_cost', 'Chi phí bán hàng khác', 'Other selling costs', 'その他販売費', 6),
  ('condo_fee', 'Phí chung cư / quản lý', 'Condo / management fee', '管理費', 0),
  ('electricity', 'Điện', 'Electricity', '電気', 1),
  ('furniture_appliance', 'Nội thất / đồ gia dụng', 'Furniture / appliances', '家具・家電', 2),
  ('gas', 'Gas', 'Gas', 'ガス', 3),
  ('home_repair', 'Sửa chữa / bảo trì nhà', 'Home repairs', '住居修理', 4),
  ('internet', 'Internet', 'Internet', 'インターネット', 5),
  ('mortgage_installment', 'Trả góp nhà', 'Mortgage installment', '住宅ローン', 6),
  ('phone', 'Điện thoại', 'Phone', '携帯・電話', 7),
  ('rent', 'Tiền nhà', 'Rent', '家賃', 8),
  ('water', 'Nước', 'Water', '水道', 9),
  ('baby_food', 'Sữa / đồ ăn dặm', 'Milk / baby food', 'ミルク・離乳食', 0),
  ('baby_gear', 'Xe đẩy / nôi / ghế ăn / đồ sơ sinh', 'Stroller / crib / baby gear', 'ベビーカー・ベビー用品', 1),
  ('child_extracurricular', 'Hoạt động vui chơi', 'Leisure & play', 'レジャー・遊び', 2),
  ('child_medical', 'Khám bệnh cho bé', 'Child doctor visits', '子どもの通院', 3),
  ('child_medicine', 'Thuốc / vitamin cho bé', 'Child medicine / vitamins', '子どもの薬・ビタミン', 4),
  ('child_supplies', 'Quần áo / đồ dùng cho bé', 'Baby clothes / supplies', '子ども用品', 5),
  ('child_toys', 'Đồ chơi', 'Toys', 'おもちゃ', 6),
  ('child_tuition', 'Học phí / giữ trẻ / mầm non', 'Tuition / childcare', '学費・保育料', 7),
  ('childcare', 'Trông trẻ / babysitter', 'Babysitting', '保育・ベビーシッター', 8),
  ('diapers_milk', 'Bỉm / tã', 'Diapers / milk', 'おむつ・ミルク', 9),
  ('school_books_supplies', 'Sách / học cụ cho bé', 'School books / supplies', '教材・学用品', 10),
  ('family_other', 'Chi khác cho con', 'Other child expenses', 'その他子ども費', 11),
  ('car_wash', 'Rửa xe', 'Car wash', '洗車', 0),
  ('fuel', 'Xăng xe', 'Fuel', 'ガソリン', 1),
  ('grab_taxi', 'Grab / taxi', 'Rideshare / taxi', '配車・タクシー', 2),
  ('parking', 'Gửi xe', 'Parking', '駐車場', 3),
  ('public_transport', 'Xe buýt / tàu / vé xe', 'Bus / train / tickets', 'バス・電車・乗車券', 4),
  ('tolls', 'Phí cầu đường', 'Tolls', '高速料金', 5),
  ('vehicle_insurance', 'Bảo hiểm xe', 'Vehicle insurance', '自動車保険', 6),
  ('vehicle_maintenance', 'Bảo dưỡng xe', 'Vehicle maintenance', '車両メンテナンス', 7),
  ('vehicle_registration', 'Đăng kiểm / giấy tờ xe', 'Vehicle registration', '車検・登録', 8),
  ('vehicle_repair', 'Sửa xe', 'Vehicle repairs', '車両修理', 9),
  ('accessories', 'Phụ kiện', 'Accessories', 'アクセサリー', 0),
  ('clothes', 'Quần áo', 'Clothing', '衣類', 1),
  ('cosmetics_skincare', 'Mỹ phẩm / skincare', 'Cosmetics / skincare', 'コスメ・スキンケア', 2),
  ('footwear', 'Giày dép', 'Footwear', '靴', 3),
  ('personal_care', 'Chăm sóc cá nhân', 'Personal care', 'パーソナルケア', 4),
  ('personal_supplies', 'Đồ dùng cá nhân', 'Personal supplies', '個人用品', 5),
  ('dental', 'Nha khoa', 'Dental', '歯科', 0),
  ('fitness_gym', 'Thể thao / gym', 'Fitness / gym', 'ジム・フィットネス', 1),
  ('health_insurance', 'Bảo hiểm sức khỏe', 'Health insurance', '健康保険', 2),
  ('hospital', 'Bệnh viện / viện phí', 'Hospital', '病院', 3),
  ('lab_tests', 'Xét nghiệm', 'Lab tests', '検査', 4),
  ('medical_checkup', 'Khám bệnh', 'Medical checkup', '健康診断', 5),
  ('medicine', 'Thuốc', 'Medicine', '薬', 6),
  ('supplements', 'Thực phẩm bổ sung', 'Supplements', 'サプリメント', 7),
  ('charity', 'Từ thiện', 'Charity', 'チャリティー', 0),
  ('family_support_expense', 'Hỗ trợ người thân', 'Family support', '親族支援', 1),
  ('gifts_ceremonies', 'Hiếu hỉ', 'Gifts / ceremonies', '贈り物・冠婚葬祭', 2),
  ('parents_support_expense', 'Biếu ông bà / cha mẹ', 'Parents / grandparents support', '親・祖父母への支援', 3),
  ('parties_gatherings', 'Tiệc gia đình / liên hoan', 'Parties / gatherings', 'パーティー・集まり', 4),
  ('relationship_gifts', 'Quà tặng', 'Relationship gifts', '交際ギフト', 5),
  ('books_music', 'Sách / truyện / nhạc', 'Books / music', '本・音楽', 0),
  ('coffee_friends', 'Cà phê gặp bạn bè', 'Coffee with friends', '友人とのカフェ', 1),
  ('games_apps', 'Game / app', 'Games / apps', 'ゲーム・アプリ', 2),
  ('hobbies', 'Sở thích cá nhân', 'Hobbies', '趣味', 3),
  ('movies_leisure', 'Xem phim / đi chơi', 'Movies / leisure', '映画・レジャー', 4),
  ('subscriptions', 'Subscription giải trí', 'Entertainment subscriptions', '娯楽サブスク', 5),
  ('travel', 'Du lịch', 'Travel', '旅行', 6),
  ('business_travel', 'Di chuyển công việc', 'Business travel', '出張・移動', 0),
  ('client_entertainment', 'Tiếp khách / gặp đối tác', 'Client entertainment', '接待・取引先', 1),
  ('courses', 'Khóa học', 'Courses', '講座', 2),
  ('exams_certificates', 'Thi cử / chứng chỉ', 'Exams / certificates', '試験・資格', 3),
  ('professional_books', 'Sách / tài liệu', 'Professional books', '専門書・資料', 4),
  ('work_software_subscriptions', 'Phần mềm / subscription', 'Software / subscriptions', 'ソフトウェア・サブスク', 5),
  ('work_tools', 'Dụng cụ học tập / làm việc', 'Study / work tools', '学習・仕事道具', 6),
  ('banking_fees', 'Phí ngân hàng', 'Bank fees', '銀行手数料', 0),
  ('fines_fees', 'Phạt / lệ phí', 'Fines / charges', '罰金・諸費用', 1),
  ('insurance', 'Bảo hiểm nhân thọ', 'Life insurance', '生命保険', 2),
  ('loan_interest', 'Lãi vay', 'Loan interest', '借入利息', 3),
  ('loan_repayment', 'Trả góp', 'Installment repayment', 'ローン返済', 4),
  ('taxes_fees', 'Thuế / phí', 'Taxes / fees', '税金・手数料', 5),
  ('other_obligations', 'Nghĩa vụ tài chính khác', 'Other financial obligations', 'その他金融支払い', 6),
  ('pet_food', 'Thức ăn thú cưng', 'Pet food', 'ペットフード', 0),
  ('pet_grooming', 'Grooming / chăm sóc', 'Pet grooming', 'ペットトリミング', 1),
  ('pet_medical', 'Khám / thuốc thú cưng', 'Pet medical', 'ペット医療', 2),
  ('pet_supplies', 'Đồ dùng thú cưng', 'Pet supplies', 'ペット用品', 3),
  ('pet_other', 'Chi khác cho thú cưng', 'Other pet expenses', 'その他ペット費', 4),
  ('balance_adjustment_expense', 'Điều chỉnh số dư', 'Balance adjustment', '残高調整', 0),
  ('salary', 'Lương chính', 'Main salary', '主給与', 0),
  ('side_salary', 'Lương phụ', 'Side salary', '副収入', 1),
  ('allowance', 'Phụ cấp', 'Allowance', '手当', 2),
  ('bonus', 'Thưởng', 'Bonus', 'ボーナス', 3),
  ('commission', 'Hoa hồng', 'Commission', 'コミッション', 4),
  ('freelance', 'Làm thêm / freelance', 'Side work / freelance', '副業・フリーランス', 5),
  ('overtime', 'OT / tăng ca', 'Overtime', '残業代', 6),
  ('business_profit', 'Lợi nhuận kinh doanh', 'Business profit', '事業利益', 0),
  ('online_collaborator_income', 'Thu từ online', 'Online income', 'オンライン収入', 1),
  ('sales', 'Doanh thu bán hàng', 'Sales revenue', '売上', 2),
  ('service_revenue', 'Thu dịch vụ', 'Service revenue', 'サービス収入', 3),
  ('other_business_income', 'Thu kinh doanh khác', 'Other business income', 'その他事業収入', 4),
  ('bank_interest', 'Lãi ngân hàng', 'Bank interest', '銀行利息', 0),
  ('dividends', 'Cổ tức', 'Dividends', '配当', 1),
  ('investment_gain', 'Lãi đầu tư', 'Investment gains', '投資利益', 2),
  ('loan_interest_received', 'Lãi cho vay', 'Loan interest received', '貸付利息', 3),
  ('other_financial_income', 'Thu nhập tài chính khác', 'Other financial income', 'その他金融収入', 4),
  ('cashback', 'Cashback', 'Cashback', 'キャッシュバック', 0),
  ('expense_recovery', 'Thu hồi khoản đã chi hộ', 'Expense recovery', '立替回収', 1),
  ('insurance_payout', 'Bảo hiểm chi trả / hoàn tiền', 'Insurance payout / refund', '保険金・返金', 2),
  ('people_repayment', 'Người khác trả lại tiền', 'Repayment from others', '返済受取', 3),
  ('refund', 'Hoàn tiền mua hàng', 'Purchase refund', '購入返金', 4),
  ('reimbursement', 'Hoàn ứng', 'Reimbursement', '立替精算', 5),
  ('child_allowance', 'Trợ cấp con nhỏ', 'Child allowance', '児童手当', 0),
  ('gift', 'Được tặng', 'Gift received', '贈与', 1),
  ('maternity_allowance', 'Trợ cấp thai sản', 'Maternity allowance', '出産・育児手当', 2),
  ('subsidy', 'Trợ cấp xã hội', 'Social subsidy', '社会手当', 3),
  ('support_received', 'Học bổng / hỗ trợ học tập', 'Scholarship / study support', '奨学金・学習支援', 4),
  ('family_support', 'Gia đình hỗ trợ', 'Family support received', '家族からの支援', 5),
  ('liquidate_household', 'Thanh lý đồ gia dụng', 'Household liquidation', '家財売却', 0),
  ('sell_used_items', 'Bán đồ cũ', 'Used item sales', '不用品売却', 1),
  ('other_liquidation_income', 'Thu khác từ thanh lý', 'Other liquidation income', 'その他売却収入', 2),
  ('balance_adjustment_income', 'Điều chỉnh số dư', 'Balance adjustment', '残高調整', 0);

update public.transaction_categories c
set
  name = l.name_vi,
  name_english = l.name_en,
  name_japanese = l.name_ja,
  sort_order = l.sort_order,
  sync_version = c.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_localized_names l
where c.is_system = true
  and c.system_key = l.system_key
  and (
    c.name is distinct from l.name_vi
    or c.name_english is distinct from l.name_en
    or c.name_japanese is distinct from l.name_ja
    or c.sort_order is distinct from l.sort_order
  );

create temporary table mistia_category_language_duplicate_map on commit drop as
with ranked as (
  select
    c.id as old_id,
    first_value(c.id) over (
      partition by c.user_id, c.system_key
      order by
        case when c.deleted_at is null then 0 else 1 end,
        case when c.is_archived is false then 0 else 1 end,
        c.sync_version desc,
        c.updated_at desc,
        c.created_at asc,
        c.id asc
    ) as keep_id,
    row_number() over (
      partition by c.user_id, c.system_key
      order by
        case when c.deleted_at is null then 0 else 1 end,
        case when c.is_archived is false then 0 else 1 end,
        c.sync_version desc,
        c.updated_at desc,
        c.created_at asc,
        c.id asc
    ) as keep_rank
  from public.transaction_categories c
  join mistia_category_localized_names l
    on l.system_key = c.system_key
  where c.is_system = true
    and c.system_key is not null
)
select old_id, keep_id
from ranked
where keep_rank > 1;

update public.transaction_categories child
set
  parent_category_id = m.keep_id,
  sync_version = child.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where child.parent_category_id = m.old_id;

update public.ledger_transactions t
set
  category_id = m.keep_id,
  sync_version = t.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where t.category_id = m.old_id;

update public.budget_plans b
set
  category_id = m.keep_id,
  sync_version = b.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where b.category_id = m.old_id;

update public.recurring_bill_plans r
set
  category_id = m.keep_id,
  sync_version = r.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where r.category_id = m.old_id;

delete from public.family_permission_requests old_request
using mistia_category_language_duplicate_map m
where old_request.resource_type = 'category'
  and old_request.resource_id = m.old_id
  and exists (
    select 1
    from public.family_permission_requests keep_request
    where keep_request.family_id = old_request.family_id
      and keep_request.requester_user_id = old_request.requester_user_id
      and keep_request.recipient_user_id = old_request.recipient_user_id
      and keep_request.resource_type = old_request.resource_type
      and keep_request.resource_id = m.keep_id
      and keep_request.permission_scope = old_request.permission_scope
  );

update public.family_permission_requests r
set
  resource_id = m.keep_id,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where r.resource_type = 'category'
  and r.resource_id = m.old_id;

delete from public.family_permission_grants old_grant
using mistia_category_language_duplicate_map m
where old_grant.resource_type = 'category'
  and old_grant.resource_id = m.old_id
  and exists (
    select 1
    from public.family_permission_grants keep_grant
    where keep_grant.grantee_user_id = old_grant.grantee_user_id
      and keep_grant.owner_user_id = old_grant.owner_user_id
      and keep_grant.resource_type = old_grant.resource_type
      and keep_grant.resource_id = m.keep_id
      and keep_grant.permission_scope = old_grant.permission_scope
  );

update public.family_permission_grants g
set
  resource_id = m.keep_id,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where g.resource_type = 'category'
  and g.resource_id = m.old_id;

update public.family_notifications n
set
  resource_id = m.keep_id,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where n.resource_type = 'category'
  and n.resource_id = m.old_id;

delete from public.transaction_categories c
using mistia_category_language_duplicate_map m
where c.id = m.old_id;

-- Hard delete system category records that are no longer part of the active Vietnamese-backed catalog.
delete from public.transaction_categories c
where c.is_system = true
  and c.system_key is not null
  and not exists (
    select 1
    from mistia_category_localized_names l
    where l.system_key = c.system_key
  );
