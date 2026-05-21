create temporary table mistia_category_localized_names (
  system_key text primary key,
  name_vi text not null,
  name_en text not null,
  name_ja text not null
) on commit drop;

insert into mistia_category_localized_names (system_key, name_vi, name_en, name_ja)
values
  ('parent_expense_food', 'Sinh hoạt', 'Essentials', '生活費'),
  ('parent_expense_cost_of_goods', 'Tiền hàng', 'Cost of goods', '仕入れ'),
  ('parent_expense_home_bills', 'Nhà ở & hóa đơn', 'Housing & bills', '住居・請求'),
  ('parent_expense_family_children', 'Con cái', 'Children', '子ども'),
  ('parent_expense_transport_vehicle', 'Đi lại & xe cộ', 'Transport & vehicle', '交通・車'),
  ('parent_expense_personal_shopping', 'Mua sắm', 'Shopping', '買い物'),
  ('parent_expense_health', 'Sức khỏe', 'Health', '健康'),
  ('parent_expense_family_relations', 'Gia đình & quan hệ', 'Family & relationships', '家族・交際'),
  ('parent_expense_entertainment_social', 'Giải trí', 'Entertainment', '娯楽'),
  ('parent_expense_work_study', 'Học tập & công việc', 'Study & work', '学習・仕事'),
  ('parent_expense_financial_obligations', 'Tài chính & nghĩa vụ', 'Finance & obligations', '金融・支払い'),
  ('parent_expense_pet_care', 'Thú cưng', 'Pets', 'ペット'),
  ('parent_expense_uncategorized', 'Chi khác', 'Other expenses', 'その他支出'),
  ('parent_income_work', 'Lương & công việc', 'Salary & work', '給与・仕事'),
  ('parent_income_sales_other', 'Kinh doanh', 'Business', '事業'),
  ('parent_income_investment_return', 'Đầu tư & tài chính', 'Investment & finance', '投資・金融'),
  ('parent_income_refund_adjustment', 'Hoàn lại & bồi hoàn', 'Refunds & reimbursements', '返金・調整'),
  ('parent_income_support_gift', 'Hỗ trợ & trợ cấp', 'Support & benefits', '支援・手当'),
  ('parent_income_liquidation', 'Thanh lý', 'Liquidation', '売却'),
  ('parent_income_uncategorized', 'Thu khác', 'Other income', 'その他収入'),
  ('grocery', 'Đi chợ', 'Groceries', '食料品'),
  ('daily_supplies', 'Đồ tiêu dùng', 'Daily supplies', '日用品'),
  ('dine_out', 'Ăn ngoài', 'Dining out', '外食'),
  ('business_meals', 'Ăn uống công việc', 'Business meals', '会食'),
  ('cafe_tea', 'Cafe / trà sữa', 'Cafe / milk tea', 'カフェ・ミルクティー'),
  ('food_delivery', 'Đặt đồ ăn', 'Food delivery', 'フードデリバリー'),
  ('snacks', 'Ăn vặt / bánh kẹo', 'Snacks', 'おやつ'),
  ('small_appliances', 'Đồ gia dụng nhỏ', 'Small home goods', '小型家電'),
  ('import_goods', 'Nhập hàng', 'Inventory purchases', '仕入れ'),
  ('goods_sourcing', 'Chi phí lấy hàng', 'Sourcing costs', '仕入れ費用'),
  ('shipping_fee', 'Phí vận chuyển hàng', 'Shipping fees', '配送料'),
  ('packaging', 'Đóng gói / bao bì', 'Packaging', '梱包材'),
  ('platform_fee', 'Chi phí sàn', 'Platform fees', 'プラットフォーム手数料'),
  ('marketing_ads', 'Marketing / quảng cáo', 'Marketing / ads', 'マーケティング・広告'),
  ('other_sales_cost', 'Chi phí bán hàng khác', 'Other selling costs', 'その他販売費'),
  ('rent', 'Tiền nhà', 'Rent', '家賃'),
  ('mortgage_installment', 'Trả góp nhà', 'Mortgage installment', '住宅ローン'),
  ('electricity', 'Điện', 'Electricity', '電気'),
  ('water', 'Nước', 'Water', '水道'),
  ('internet', 'Internet', 'Internet', 'インターネット'),
  ('phone', 'Điện thoại', 'Phone', '携帯・電話'),
  ('gas', 'Gas', 'Gas', 'ガス'),
  ('condo_fee', 'Phí chung cư / quản lý', 'Condo / management fee', '管理費'),
  ('home_repair', 'Sửa chữa / bảo trì nhà', 'Home repairs', '住居修理'),
  ('furniture_appliance', 'Nội thất / đồ gia dụng', 'Furniture / appliances', '家具・家電'),
  ('diapers_milk', 'Bỉm / tã', 'Diapers / milk', 'おむつ・ミルク'),
  ('baby_food', 'Sữa / đồ ăn dặm', 'Milk / baby food', 'ミルク・離乳食'),
  ('child_supplies', 'Quần áo / đồ dùng cho bé', 'Baby clothes / supplies', '子ども用品'),
  ('child_toys', 'Đồ chơi', 'Toys', 'おもちゃ'),
  ('school_books_supplies', 'Sách / học cụ cho bé', 'School books / supplies', '教材・学用品'),
  ('child_tuition', 'Học phí / giữ trẻ / mầm non', 'Tuition / childcare', '学費・保育料'),
  ('child_extracurricular', 'Hoạt động ngoại khóa', 'Extracurricular activities', '習い事・課外活動'),
  ('child_medical', 'Khám bệnh cho bé', 'Child doctor visits', '子どもの通院'),
  ('child_medicine', 'Thuốc / vitamin cho bé', 'Child medicine / vitamins', '子どもの薬・ビタミン'),
  ('baby_gear', 'Xe đẩy / nôi / ghế ăn / đồ sơ sinh', 'Stroller / crib / baby gear', 'ベビーカー・ベビー用品'),
  ('childcare', 'Trông trẻ / babysitter', 'Babysitting', '保育・ベビーシッター'),
  ('family_other', 'Chi khác cho con', 'Other child expenses', 'その他子ども費'),
  ('fuel', 'Xăng xe', 'Fuel', 'ガソリン'),
  ('parking', 'Gửi xe', 'Parking', '駐車場'),
  ('grab_taxi', 'Grab / taxi', 'Rideshare / taxi', '配車・タクシー'),
  ('public_transport', 'Xe buýt / tàu / vé xe', 'Bus / train / tickets', 'バス・電車・乗車券'),
  ('vehicle_maintenance', 'Bảo dưỡng xe', 'Vehicle maintenance', '車両メンテナンス'),
  ('vehicle_repair', 'Sửa xe', 'Vehicle repairs', '車両修理'),
  ('car_wash', 'Rửa xe', 'Car wash', '洗車'),
  ('tolls', 'Phí cầu đường', 'Tolls', '高速料金'),
  ('vehicle_insurance', 'Bảo hiểm xe', 'Vehicle insurance', '自動車保険'),
  ('vehicle_registration', 'Đăng kiểm / giấy tờ xe', 'Vehicle registration', '車検・登録'),
  ('clothes', 'Quần áo', 'Clothing', '衣類'),
  ('footwear', 'Giày dép', 'Footwear', '靴'),
  ('cosmetics_skincare', 'Mỹ phẩm / skincare', 'Cosmetics / skincare', 'コスメ・スキンケア'),
  ('personal_care', 'Chăm sóc cá nhân', 'Personal care', 'パーソナルケア'),
  ('accessories', 'Phụ kiện', 'Accessories', 'アクセサリー'),
  ('personal_supplies', 'Đồ dùng cá nhân', 'Personal supplies', '個人用品'),
  ('medical_checkup', 'Khám bệnh', 'Medical checkup', '健康診断'),
  ('medicine', 'Thuốc', 'Medicine', '薬'),
  ('lab_tests', 'Xét nghiệm', 'Lab tests', '検査'),
  ('dental', 'Nha khoa', 'Dental', '歯科'),
  ('hospital', 'Bệnh viện / viện phí', 'Hospital', '病院'),
  ('health_insurance', 'Bảo hiểm sức khỏe', 'Health insurance', '健康保険'),
  ('fitness_gym', 'Thể thao / gym', 'Fitness / gym', 'ジム・フィットネス'),
  ('supplements', 'Thực phẩm bổ sung', 'Supplements', 'サプリメント'),
  ('gifts_ceremonies', 'Hiếu hỉ', 'Gifts / ceremonies', '贈り物・冠婚葬祭'),
  ('relationship_gifts', 'Quà tặng', 'Relationship gifts', '交際ギフト'),
  ('parents_support_expense', 'Biếu ông bà / cha mẹ', 'Parents / grandparents support', '親・祖父母への支援'),
  ('family_support_expense', 'Hỗ trợ người thân', 'Family support', '親族支援'),
  ('parties_gatherings', 'Tiệc gia đình / liên hoan', 'Parties / gatherings', 'パーティー・集まり'),
  ('charity', 'Từ thiện', 'Charity', 'チャリティー'),
  ('movies_leisure', 'Xem phim / đi chơi', 'Movies / leisure', '映画・レジャー'),
  ('travel', 'Du lịch', 'Travel', '旅行'),
  ('games_apps', 'Game / app', 'Games / apps', 'ゲーム・アプリ'),
  ('books_music', 'Sách / truyện / nhạc', 'Books / music', '本・音楽'),
  ('subscriptions', 'Subscription giải trí', 'Entertainment subscriptions', '娯楽サブスク'),
  ('hobbies', 'Sở thích cá nhân', 'Hobbies', '趣味'),
  ('coffee_friends', 'Cà phê gặp bạn bè', 'Coffee with friends', '友人とのカフェ'),
  ('work_tools', 'Dụng cụ học tập / làm việc', 'Study / work tools', '学習・仕事道具'),
  ('work_software_subscriptions', 'Phần mềm / subscription', 'Software / subscriptions', 'ソフトウェア・サブスク'),
  ('client_entertainment', 'Tiếp khách / gặp đối tác', 'Client entertainment', '接待・取引先'),
  ('business_travel', 'Di chuyển công việc', 'Business travel', '出張・移動'),
  ('courses', 'Khóa học', 'Courses', '講座'),
  ('professional_books', 'Sách / tài liệu', 'Professional books', '専門書・資料'),
  ('exams_certificates', 'Thi cử / chứng chỉ', 'Exams / certificates', '試験・資格'),
  ('insurance', 'Bảo hiểm nhân thọ', 'Life insurance', '生命保険'),
  ('taxes_fees', 'Thuế / phí', 'Taxes / fees', '税金・手数料'),
  ('banking_fees', 'Phí ngân hàng', 'Bank fees', '銀行手数料'),
  ('loan_interest', 'Lãi vay', 'Loan interest', '借入利息'),
  ('loan_repayment', 'Trả góp', 'Installment repayment', 'ローン返済'),
  ('fines_fees', 'Phạt / lệ phí', 'Fines / charges', '罰金・諸費用'),
  ('other_obligations', 'Nghĩa vụ tài chính khác', 'Other financial obligations', 'その他金融支払い'),
  ('pet_food', 'Thức ăn thú cưng', 'Pet food', 'ペットフード'),
  ('pet_medical', 'Khám / thuốc thú cưng', 'Pet medical', 'ペット医療'),
  ('pet_supplies', 'Đồ dùng thú cưng', 'Pet supplies', 'ペット用品'),
  ('pet_grooming', 'Grooming / chăm sóc', 'Pet grooming', 'ペットトリミング'),
  ('pet_other', 'Chi khác cho thú cưng', 'Other pet expenses', 'その他ペット費'),
  ('balance_adjustment_expense', 'Điều chỉnh số dư', 'Balance adjustment', '残高調整'),
  ('salary', 'Lương chính', 'Main salary', '主給与'),
  ('side_salary', 'Lương phụ', 'Side salary', '副収入'),
  ('bonus', 'Thưởng', 'Bonus', 'ボーナス'),
  ('allowance', 'Phụ cấp', 'Allowance', '手当'),
  ('commission', 'Hoa hồng', 'Commission', 'コミッション'),
  ('freelance', 'Làm thêm / freelance', 'Side work / freelance', '副業・フリーランス'),
  ('overtime', 'OT / tăng ca', 'Overtime', '残業代'),
  ('sales', 'Doanh thu bán hàng', 'Sales revenue', '売上'),
  ('service_revenue', 'Thu dịch vụ', 'Service revenue', 'サービス収入'),
  ('business_profit', 'Lợi nhuận kinh doanh', 'Business profit', '事業利益'),
  ('online_collaborator_income', 'Thu từ online', 'Online income', 'オンライン収入'),
  ('other_business_income', 'Thu kinh doanh khác', 'Other business income', 'その他事業収入'),
  ('bank_interest', 'Lãi ngân hàng', 'Bank interest', '銀行利息'),
  ('dividends', 'Cổ tức', 'Dividends', '配当'),
  ('investment_gain', 'Lãi đầu tư', 'Investment gains', '投資利益'),
  ('loan_interest_received', 'Lãi cho vay', 'Loan interest received', '貸付利息'),
  ('other_financial_income', 'Thu nhập tài chính khác', 'Other financial income', 'その他金融収入'),
  ('refund', 'Hoàn tiền mua hàng', 'Purchase refund', '購入返金'),
  ('cashback', 'Cashback', 'Cashback', 'キャッシュバック'),
  ('reimbursement', 'Hoàn ứng', 'Reimbursement', '立替精算'),
  ('people_repayment', 'Người khác trả lại tiền', 'Repayment from others', '返済受取'),
  ('expense_recovery', 'Thu hồi khoản đã chi hộ', 'Expense recovery', '立替回収'),
  ('insurance_payout', 'Bảo hiểm chi trả / hoàn tiền', 'Insurance payout / refund', '保険金・返金'),
  ('gift', 'Được tặng', 'Gift received', '贈与'),
  ('family_support', 'Gia đình hỗ trợ', 'Family support received', '家族からの支援'),
  ('child_allowance', 'Trợ cấp con nhỏ', 'Child allowance', '児童手当'),
  ('maternity_allowance', 'Trợ cấp thai sản', 'Maternity allowance', '出産・育児手当'),
  ('subsidy', 'Trợ cấp xã hội', 'Social subsidy', '社会手当'),
  ('support_received', 'Học bổng / hỗ trợ học tập', 'Scholarship / study support', '奨学金・学習支援'),
  ('sell_used_items', 'Bán đồ cũ', 'Used item sales', '不用品売却'),
  ('liquidate_household', 'Thanh lý đồ gia dụng', 'Household liquidation', '家財売却'),
  ('other_liquidation_income', 'Thu khác từ thanh lý', 'Other liquidation income', 'その他売却収入'),
  ('balance_adjustment_income', 'Điều chỉnh số dư', 'Balance adjustment', '残高調整');

update public.transaction_categories c
set
  name = l.name_vi,
  name_english = l.name_en,
  name_japanese = l.name_ja,
  sync_version = c.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_localized_names l
where c.is_system = true
  and c.system_key = l.system_key
  and (
    c.name is distinct from l.name_vi
    or c.name_english is distinct from l.name_en
    or c.name_japanese is distinct from l.name_ja
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
