-- V9 additive account metadata. Never rewrite legacy amounts, icons or revisions.
ALTER TABLE accounts ADD COLUMN account_type TEXT NOT NULL DEFAULT 'other_asset';
ALTER TABLE accounts ADD COLUMN issuer_key TEXT NOT NULL DEFAULT '';
ALTER TABLE accounts ADD COLUMN card_tail TEXT NOT NULL DEFAULT '' CHECK(card_tail='' OR (length(card_tail)=4 AND card_tail NOT GLOB '*[^0-9]*'));
ALTER TABLE accounts ADD COLUMN note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=500);
UPDATE accounts SET account_type=CASE
 WHEN icon_key IN ('icbk','icbk_color','bkch','bkch_color','ccbc','ccbc_color','aboc','aboc_color','cmb','cmb_color')
   OR (icon_key GLOB 'bank_*' AND icon_key<>'bank_card')
 THEN CASE WHEN kind='liability' THEN 'credit_card' ELSE 'debit_card' END
 WHEN kind='liability' THEN CASE icon_key WHEN 'huabei' THEN 'huabei' WHEN 'huabei_color' THEN 'huabei' WHEN 'jiebei' THEN 'jiebei' WHEN 'jiebei_color' THEN 'jiebei' WHEN 'credit_card' THEN 'credit_card' ELSE 'other_credit' END
 WHEN icon_key='cash' THEN 'cash'
 WHEN icon_key IN ('wechat_pay','wechat_pay_color') THEN 'wechat'
 WHEN icon_key IN ('alipay','alipay_color') THEN 'alipay'
 ELSE 'other_asset' END;
UPDATE accounts SET issuer_key=CASE WHEN icon_key GLOB '*_color' THEN substr(icon_key,1,length(icon_key)-6) ELSE icon_key END
 WHERE account_type IN ('debit_card','credit_card') AND icon_key<>'credit_card';
