/* ============================================================================
   CRM CUSTOMER RETENTION & REVENUE LEAK ANALYSIS
   ----------------------------------------------------------------------------
   THE STORY IN ONE LINE:
   The company keeps getting new customers every month, but the money isn't
   growing the way it should. This project finds out WHY.

   THE ANSWER (spoiler): Customers are leaving very fast (about half of them).
   The company looks like it's growing only because new customers keep pouring
   in faster than old ones leave - like filling a bucket that has a big hole
   in the bottom.

   ABOUT THE DATA:
   There are 2 tables. The most important one is "subscription_history".
   In this table, EACH ROW = ONE MONTH for ONE CUSTOMER. So if a customer
   stayed 12 months, they have 12 rows (like 12 monthly bills). This one fact
   is the key to understanding everything below.

   HOW THIS FILE IS ORGANIZED:
     PART 1 - Clean up the data and connect the tables properly
     PART 2 - Double-check the data before trusting any numbers
     PART 3 - Find the main problem (are customers leaving, downgrading, or upgrading?)
     PART 4 - Measure the money problem (revenue and how much old customers keep)
     PART 5 - Dig into the leaving problem (WHEN, WHO, and WHY people leave)
     PART 6 - Prove that new customers are what's hiding the problem
     PART 7 - Build a table for the final chart
   ============================================================================ */


/* ============================================================================
   PART 1 - CLEAN UP THE DATA AND CONNECT THE TABLES

   When the data was first loaded, all the columns had the wrong "type" (for
   example, money was stored as plain text, dates as text). Here we fix each
   column to the correct type (money as numbers, dates as real dates, yes/no
   flags as true/false). We also mark the ID column of each table and connect
   the tables together, so the database knows they relate to each other.
   ============================================================================ */

-- ---- customers table (the main table; every other table connects to this one) ----
ALTER TABLE customers ALTER COLUMN customer_id             TYPE bigint  USING customer_id::bigint;
ALTER TABLE customers ALTER COLUMN signup_date             TYPE date;
ALTER TABLE customers ALTER COLUMN acquisition_channel     TYPE varchar(50);
ALTER TABLE customers ALTER COLUMN acquisition_month       TYPE varchar(20);   -- switch to date if the values look like 2024-03-01
ALTER TABLE customers ALTER COLUMN acquisition_campaign_id TYPE varchar(50);
ALTER TABLE customers ALTER COLUMN region                  TYPE varchar(50);
ALTER TABLE customers ALTER COLUMN device_type             TYPE varchar(30);
ALTER TABLE customers ALTER COLUMN first_order_date        TYPE date;
ALTER TABLE customers ALTER COLUMN customer_status         TYPE varchar(20);
ALTER TABLE customers ALTER COLUMN date_of_birth           TYPE date;
ALTER TABLE customers ALTER COLUMN gender                  TYPE varchar(20);
ALTER TABLE customers ADD PRIMARY KEY (customer_id);   -- customer_id is the unique ID for each customer

-- ---- subscription_history table (THE MAIN ONE: one row = one month for one customer) ----
ALTER TABLE subscription_history ALTER COLUMN subscription_id   TYPE bigint       USING subscription_id::bigint;
ALTER TABLE subscription_history ALTER COLUMN customer_id       TYPE bigint       USING customer_id::bigint;
ALTER TABLE subscription_history ALTER COLUMN subscription_tier TYPE varchar(30);   -- the plan: Basic or Premium
ALTER TABLE subscription_history ALTER COLUMN start_date        TYPE date;
ALTER TABLE subscription_history ALTER COLUMN end_date          TYPE date;
ALTER TABLE subscription_history ALTER COLUMN monthly_fee       TYPE numeric(12,2) USING monthly_fee::numeric;   -- money they pay that month
ALTER TABLE subscription_history ALTER COLUMN churn_flag        TYPE boolean       USING churn_flag::int::boolean;   -- true = they left
ALTER TABLE subscription_history ALTER COLUMN churn_reason      TYPE varchar(100);  -- why they left
ALTER TABLE subscription_history ALTER COLUMN reactivation_flag TYPE boolean       USING reactivation_flag::int::boolean;
ALTER TABLE subscription_history ADD PRIMARY KEY (subscription_id);
ALTER TABLE subscription_history ADD FOREIGN KEY (customer_id) REFERENCES customers(customer_id);  -- connect to customers table

/* ============================================================================
   PART 2 - DOUBLE-CHECK THE DATA BEFORE TRUSTING IT

   Before we believe any numbers, we make sure we understand the data and that
   our counting is correct.
   ============================================================================ */

-- Q1: Does one customer have many rows, or just one?
--     WHY WE ASK: it tells us what one row means.
--     WHAT WE FOUND: yes, customers have many rows each.
SELECT customer_id, COUNT(*) AS number_of_rows
FROM subscription_history
GROUP BY customer_id
HAVING COUNT(*) > 1
LIMIT 5;

-- Q2: Look at ONE customer's rows closely to see what a single row actually is.
--     WHAT WE FOUND (the big one): each row is ONE MONTH. The same fee repeats
--     month after month. So this table is like a stack of monthly bills.
SELECT subscription_id, subscription_tier, start_date, end_date, monthly_fee, churn_flag
FROM subscription_history
WHERE customer_id = 3
ORDER BY start_date;

-- Q3: Are we accidentally counting the same leaver many times?
--     WHY WE ASK: if "left" is marked on every row, our count would be too high.
--     WHAT WE FOUND: the two numbers are almost equal, so each customer who
--     left is counted only once. Our count is safe to trust.
SELECT
    COUNT(*)                    AS rows_marked_left,
    COUNT(DISTINCT customer_id) AS customers_who_left
FROM subscription_history
WHERE churn_flag = true;


/* ============================================================================
   PART 3 - FIND THE MAIN PROBLEM

   Money can leak out of a subscription business in 3 ways:
     1. Customers LEAVE completely
     2. Customers stay but pay LESS (move to a cheaper plan)
     3. Customers stay and pay MORE (move to a pricier plan) - this is good
   We count all three to see which one is the real problem.
   ============================================================================ */

-- Q4: What fraction of ALL customers have left?
--     WHAT WE FOUND: about 55% of customers have left. That's more than half.
SELECT
    (SELECT COUNT(*) FROM customers) AS total_customers,
    (SELECT COUNT(DISTINCT customer_id) FROM subscription_history WHERE churn_flag = true) AS customers_who_left;

-- Q5: How many times did a customer move to a CHEAPER plan (pay less)?
--     HOW IT WORKS: for each customer, we line up their months in order and
--     compare each month's fee to the month before. If the fee went DOWN,
--     that's a downgrade. (We keep each customer separate so we never mix up
--     one customer's fee with another's.)
--     WHAT WE FOUND: only 4,110 times - small.
WITH monthly AS (
    SELECT customer_id, start_date, monthly_fee,
           LAG(monthly_fee) OVER (PARTITION BY customer_id ORDER BY start_date) AS previous_month_fee
    FROM subscription_history
)
SELECT COUNT(*) AS times_they_paid_less
FROM monthly
WHERE monthly_fee < previous_month_fee;

-- Q6: How many times did a customer move to a PRICIER plan (pay more)?
--     Same idea as Q5, but the fee went UP.
--     WHAT WE FOUND: only 6,762 times - also small.
WITH monthly AS (
    SELECT customer_id, start_date, monthly_fee,
           LAG(monthly_fee) OVER (PARTITION BY customer_id ORDER BY start_date) AS previous_month_fee
    FROM subscription_history
)
SELECT COUNT(*) AS times_they_paid_more
FROM monthly
WHERE monthly_fee > previous_month_fee;

-- WHAT PART 3 TELLS US: about 111,000 customers LEFT, but only ~4,000 paid less
-- and ~6,000 paid more. So the big problem is clearly customers LEAVING, not
-- customers changing plans. From here on, we focus only on the leaving.


/* ============================================================================
   PART 4 - MEASURE THE MONEY PROBLEM

   Two things here:
   (a) Total monthly money coming in, and whether it's going up or down.
   (b) A key test: if we follow ONE group of customers over time (without
       adding any new ones), does their money grow or shrink?
   ============================================================================ */

-- Q7: Total money collected each month (add up everyone's fee for that month).
--     WHAT WE FOUND: the total money goes UP every month (from about 23,000 to
--     about 1.68 million) - even though so many customers are leaving. Odd, right?
--     Part 6 explains why.
SELECT
    DATE_TRUNC('month', start_date) AS month,
    SUM(monthly_fee)                AS total_money_this_month,
    COUNT(*)                        AS active_customers_this_month
FROM subscription_history
GROUP BY DATE_TRUNC('month', start_date)
ORDER BY month;

-- Q8: A quick safety check - when a customer leaves, does their last row still
--     have real money in it, or is it blank?
--     WHAT WE FOUND: the leaving rows have real money (about 13.79 on average).
--     So a customer's leaving month is simply their last paid month, and it
--     correctly counts as money. (This confirms Q7 is measuring money correctly.)
SELECT
    churn_flag,
    COUNT(*)          AS number_of_rows,
    AVG(monthly_fee)  AS average_fee,
    MIN(monthly_fee)  AS lowest_fee,
    MAX(monthly_fee)  AS highest_fee
FROM subscription_history
GROUP BY churn_flag;

-- Q9: Take ONE group - everyone who joined in Jan 2021 - and check them again
--     12 months later. We follow the SAME people (no new customers added).
--     WHAT WE FOUND: the group shrank from 1,452 people (23,109 money) to
--     766 people (13,427 money). That's about 58% of the money kept - meaning
--     this group LOST about 42% of its money in one year.
WITH cohort AS (
    SELECT DISTINCT customer_id
    FROM subscription_history
    WHERE DATE_TRUNC('month', start_date) = '2021-01-01'
)
SELECT
    DATE_TRUNC('month', s.start_date)   AS month,
    COUNT(DISTINCT s.customer_id)       AS people_still_here,
    SUM(s.monthly_fee)                  AS total_money
FROM subscription_history s
INNER JOIN cohort c ON s.customer_id = c.customer_id
WHERE DATE_TRUNC('month', s.start_date) IN ('2021-01-01', '2022-01-01')
GROUP BY DATE_TRUNC('month', s.start_date)
ORDER BY month;



	``
-- Q10: Do the same one-year check for THREE different joining months, to make
--      sure the 58% wasn't a fluke.
--      HOW IT WORKS: first we find each customer's very first month (their
--      "group"), then compare each group's money at the start vs one year later.
--      WHAT WE FOUND: all three groups kept about 58%. So this is a steady,
--      repeating pattern - not luck.
WITH cohorts AS (
    SELECT customer_id, MIN(DATE_TRUNC('month', start_date)) AS join_month
    FROM subscription_history
    GROUP BY customer_id
),
cohort_revenue AS (
    SELECT
        c.join_month,
        DATE_TRUNC('month', s.start_date) AS active_month,
        SUM(s.monthly_fee)                AS money
    FROM subscription_history s
    INNER JOIN cohorts c ON s.customer_id = c.customer_id
    GROUP BY c.join_month, DATE_TRUNC('month', s.start_date)
)
SELECT
    join_month,
    MAX(CASE WHEN active_month = join_month THEN money END)                        AS money_at_start,
    MAX(CASE WHEN active_month = join_month + INTERVAL '12 months' THEN money END) AS money_one_year_later
FROM cohort_revenue
WHERE join_month IN ('2021-01-01', '2021-07-01', '2022-01-01')
GROUP BY join_month
ORDER BY join_month;


/* ============================================================================
   PART 5 - DIG INTO THE LEAVING: WHEN, WHO, AND WHY

   Now we know leaving is the problem. Let's understand it: at what point do
   people leave, which kinds of people leave more, and for what reason.
   ============================================================================ */

-- Q11: WHEN do people leave? We count how many months each leaver stayed
--      before quitting. (Number of rows = number of months they stayed.)
--      WHAT WE FOUND: most people leave in the FIRST FEW MONTHS. About 1 in 4
--      of all leavers are gone within the first 3 months. The longer someone
--      stays, the less likely they are to leave.
WITH churned_customers AS (
    SELECT DISTINCT customer_id
    FROM subscription_history
    WHERE churn_flag = true
),
duration AS (
    SELECT s.customer_id, COUNT(*) AS months_stayed
    FROM subscription_history s
    INNER JOIN churned_customers c ON s.customer_id = c.customer_id
    GROUP BY s.customer_id
)
SELECT months_stayed, COUNT(*) AS number_of_customers
FROM duration
GROUP BY months_stayed
ORDER BY months_stayed;

-- Q12: WHO leaves - split by PLAN. We use the PERCENTAGE that left, not the raw
--      count. (A bigger plan would naturally have more leavers just because it's
--      bigger, so the percentage is the fair way to compare.)
--      WHAT WE FOUND: Basic (cheap) plan = 57.6% left, Premium (pricey) = 40.6%.
--      Cheap-plan customers leave a lot more.
SELECT
    subscription_tier,
    COUNT(DISTINCT customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN churn_flag = true THEN customer_id END) AS customers_who_left,
    ROUND(
        COUNT(DISTINCT CASE WHEN churn_flag = true THEN customer_id END) * 100.0
        / COUNT(DISTINCT customer_id), 1
    ) AS percent_who_left
FROM subscription_history
GROUP BY subscription_tier
ORDER BY percent_who_left DESC;

-- Q13: WHO leaves - split by REGION. (We join to the customers table to get the
--      region for each person.)
--      WHAT WE FOUND: every region is about the same (53-59%). So WHERE a person
--      lives does NOT explain leaving. This tells us to look elsewhere.
SELECT
    c.region,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN s.churn_flag = true THEN s.customer_id END) AS customers_who_left,
    ROUND(
        COUNT(DISTINCT CASE WHEN s.churn_flag = true THEN s.customer_id END) * 100.0
        / COUNT(DISTINCT s.customer_id), 1
    ) AS percent_who_left
FROM subscription_history s
INNER JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.region
ORDER BY percent_who_left DESC;

-- Q14: WHO leaves - split by HOW THEY WERE FOUND (the channel they came from).
--      (We join to customers to get each person's source.)
--      WHAT WE FOUND: people from paid sources leave much more - Influencer 61%
--      and Paid Ads 60% - while people who came on their own (Organic 46%) or
--      through a friend (Referral 50%) stay longer. Paid ads bring in customers
--      who don't stick around.
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN s.churn_flag = true THEN s.customer_id END) AS customers_who_left,
    ROUND(
        COUNT(DISTINCT CASE WHEN s.churn_flag = true THEN s.customer_id END) * 100.0
        / COUNT(DISTINCT s.customer_id), 1
    ) AS percent_who_left
FROM subscription_history s
INNER JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.acquisition_channel
ORDER BY percent_who_left DESC;


-- Q_GENDER: WHO leaves - split by GENDER. (We join to the customers table to
--           get each person's gender.) Like Q13/Q14, we use the PERCENTAGE that
--           left, not the raw count, so a bigger group doesn't look worse just
--           because it's bigger.
--           WHAT WE FOUND: every gender is about the same (54-56%). So gender
--           does NOT explain leaving - the reason lies elsewhere (plan, channel).
SELECT
    c.gender,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN s.churn_flag = true THEN s.customer_id END) AS customers_who_left,
    ROUND(
        COUNT(DISTINCT CASE WHEN s.churn_flag = true THEN s.customer_id END) * 100.0
        / COUNT(DISTINCT s.customer_id), 1
    ) AS percent_who_left
FROM subscription_history s
INNER JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.gender
ORDER BY percent_who_left DESC;


-- Q15: WHY do people leave? We just count each reason they gave.
--      WHAT WE FOUND: the #1 reason is "Inactivity" (they never really used the
--      product), then "Price" (too expensive), then "Competitor" (found something
--      better), then "Other". So the biggest problem is people signing up and
--      then never using the product.
SELECT
    churn_reason,
    COUNT(*) AS number_who_left
FROM subscription_history
WHERE churn_flag = true
GROUP BY churn_reason
ORDER BY number_who_left DESC;


/* ============================================================================
   PART 6 - PROVE WHY THE TOTAL MONEY STILL GOES UP

   Puzzle: half the customers leave, yet total money keeps rising (from Q7).
   The only way that happens is if new customers keep pouring in fast enough
   to cover the ones leaving. Let's prove it.
   ============================================================================ */

-- Q16: How many BRAND-NEW customers join each month? (A new customer = someone
--      whose very first month is that month.)
--      WHAT WE FOUND: new sign-ups keep growing (from about 1,500 a month to
--      about 9,000 a month). This proves the point: the company grows only
--      because new customers arrive faster than old ones leave. It's a bucket
--      with a hole - it looks full only because water keeps pouring in.
WITH first_month AS (
    SELECT customer_id, MIN(DATE_TRUNC('month', start_date)) AS first_month
    FROM subscription_history
    GROUP BY customer_id
)
SELECT
    first_month AS month,
    COUNT(*)    AS new_customers_this_month
FROM first_month
GROUP BY first_month
ORDER BY first_month;


/* ============================================================================
   PART 7 - BUILD THE TABLE FOR THE FINAL CHART

   This makes a grid: for each joining month (group), and for each month after
   they joined, how many of them are still around. Plotted, this becomes the
   "retention" chart that shows, at a glance, how fast each group melts away.
   ============================================================================ */

/* ============================================================================
   Q17 - COHORT RETENTION as PERCENTAGE 
   every group starts at 100% and shows what % is still
   active each month after. This makes all groups comparable regardless of
   their starting size.
   ============================================================================ */

WITH cohort_data AS (
    -- Step 1: tag each row with its join-group and its month
    SELECT
        s.customer_id,
        MIN(DATE_TRUNC('month', s.start_date)) OVER (PARTITION BY s.customer_id) AS join_month,
        DATE_TRUNC('month', s.start_date) AS activity_month
    FROM subscription_history s
),
month_number AS (
    -- Step 2: work out how many months after joining each row is (0, 1, 2...)
    SELECT
        customer_id,
        join_month,
        (EXTRACT(YEAR  FROM activity_month) - EXTRACT(YEAR  FROM join_month)) * 12
      + (EXTRACT(MONTH FROM activity_month) - EXTRACT(MONTH FROM join_month)) AS months_after
    FROM cohort_data
),
cohort_counts AS (
    -- Step 3: count how many of each group are active at each month
    SELECT
        join_month,
        months_after,
        COUNT(DISTINCT customer_id) AS customers
    FROM month_number
    GROUP BY join_month, months_after
)
-- Step 4: divide each month's count by the group's month-0 count -> percentage
SELECT
    join_month,
    months_after,
    customers,
    ROUND(
        customers * 100.0
        / FIRST_VALUE(customers) OVER (PARTITION BY join_month ORDER BY months_after),
        1
    ) AS retention_percent
FROM cohort_counts
ORDER BY join_month, months_after;


SELECT channel, SUM(new_customers) AS total_customer FROM marketing_spend
GROUP BY channel


