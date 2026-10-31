-- ============================================================================
-- Local SQLite Analytical Views & Queries
-- Supports Live Demonstration of Member 360 & Redemptions
-- ============================================================================

-- View: Unified Member View across all Country Tables
CREATE VIEW IF NOT EXISTS vw_all_active_members AS
SELECT *, 'IND' AS source_table_country FROM table_india
UNION ALL
SELECT *, 'USA' AS source_table_country FROM table_usa
UNION ALL
SELECT *, 'CAN' AS source_table_country FROM table_canada
UNION ALL
SELECT *, 'PHIL' AS source_table_country FROM table_philippines
UNION ALL
SELECT *, 'AU' AS source_table_country FROM table_australia
UNION ALL
SELECT *, 'OTHER' AS source_table_country FROM table_other_countries;

-- View: Member Loyalty 360 Join
CREATE VIEW IF NOT EXISTS vw_member_loyalty_360 AS
SELECT 
    m.mem_id,
    m.name,
    m.country,
    m.state,
    m.tier,
    m.age,
    m.flag AS is_active,
    m.stale_member,
    m.flight_dt,
    r.txn_id,
    r.txn_date,
    r.partner,
    r.miles_redeemed,
    r.status AS redemption_status
FROM vw_all_active_members m
LEFT JOIN fact_member_redemptions r
    ON m.mem_id = r.member_id;

-- Query: Summary by Country & Tier
SELECT 
    m.country,
    m.tier,
    COUNT(DISTINCT m.mem_id) AS total_members,
    COUNT(r.txn_id) AS total_redemptions,
    COALESCE(SUM(r.miles_redeemed), 0) AS total_miles_redeemed
FROM vw_all_active_members m
LEFT JOIN fact_member_redemptions r
    ON m.mem_id = r.member_id AND r.status = 'COMPLETED'
GROUP BY m.country, m.tier
ORDER BY total_miles_redeemed DESC;
