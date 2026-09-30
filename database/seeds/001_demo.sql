BEGIN;

INSERT INTO organizations (name, slug)
VALUES ('JAI Demo Company', 'jai-demo')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO locations (organization_id, name, code)
SELECT id, 'Demo Main Store', 'MAIN'
FROM organizations
WHERE slug = 'jai-demo'
ON CONFLICT (organization_id, code) DO NOTHING;

INSERT INTO users (email, password_hash, display_name, is_superadmin)
VALUES ('admin@jai.local', 'REPLACE_WITH_ARGON2ID_HASH', 'JAI Demo Administrator', TRUE)
ON CONFLICT (email) DO NOTHING;

INSERT INTO organization_memberships (organization_id, user_id, role)
SELECT o.id, u.id, 'owner'
FROM organizations o
CROSS JOIN users u
WHERE o.slug = 'jai-demo' AND u.email = 'admin@jai.local'
ON CONFLICT (organization_id, user_id) DO NOTHING;

INSERT INTO customers (organization_id, customer_code, full_name, mobile, city, marketing_consent)
SELECT o.id, v.code, v.name, v.mobile, v.city, v.consent
FROM organizations o
CROSS JOIN (VALUES
    ('DEMO-0001','Anita Menon','9000000001','Kochi',true),
    ('DEMO-0002','Rahul Nair','9000000002','Thrissur',false),
    ('DEMO-0003','Meera Krishnan','9000000003','Kozhikode',true)
) AS v(code,name,mobile,city,consent)
WHERE o.slug = 'jai-demo'
ON CONFLICT (organization_id, customer_code) DO NOTHING;

INSERT INTO products (organization_id, sku, name, category)
SELECT o.id, v.sku, v.name, v.category
FROM organizations o
CROSS JOIN (VALUES
    ('DEMO-SAREE-001','Demo Silk Saree','Sarees'),
    ('DEMO-MENS-001','Demo Menswear Set','Menswear'),
    ('DEMO-KIDS-001','Demo Kidswear Set','Kidswear')
) AS v(sku,name,category)
WHERE o.slug = 'jai-demo'
ON CONFLICT (organization_id, sku) DO NOTHING;

COMMIT;
