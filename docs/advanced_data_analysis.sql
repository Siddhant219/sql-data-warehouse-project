-- =========================
-- Change-Over-Time Trends
-- =========================

SELECT
	  YEAR(order_date) order_year
	, SUM(sales_amount) AS total_sales
	, AVG(sales_amount) AS avg_sales
	, SUM(product_key) AS total_products
	, SUM(customer_key) AS total_customers
	, SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date)

SELECT
	  DATETRUNC(month, order_date) order_month
	, SUM(sales_amount) AS total_sales
	, AVG(sales_amount) AS avg_sales
	, COUNT(DISTINCT product_key) AS total_products
	, COUNT(DISTINCT customer_key) AS total_customers
	, SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month, order_date) 
ORDER BY DATETRUNC(month, order_date) 

-- =========================
-- Cumulative Analysis
-- =========================

-- Calculate the total sales per month
-- and the running total of sales over time

WITH CTE AS (
	SELECT
		  DATETRUNC(month, order_date) AS order_month
		, SUM(sales_amount) AS monthly_sales
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(month, order_date)
)
SELECT 
	  order_month
	, monthly_sales
	, SUM(monthly_sales) OVER (PARTITION BY YEAR(order_month) ORDER BY order_month) AS running_total
FROM CTE;

-- Find the moving average price in above

WITH CTE AS (
	SELECT
		  DATETRUNC(month, order_date) AS order_month
		, SUM(sales_amount) AS monthly_sales
		, AVG(price) AS average_price
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(month, order_date)
)
SELECT 
	  order_month
	, monthly_sales
	, SUM(monthly_sales) OVER (PARTITION BY YEAR(order_month) ORDER BY order_month) AS running_total_sales
	, average_price
	, AVG(average_price) OVER (PARTITION BY YEAR(order_month) ORDER BY order_month) AS moving_average_price
FROM CTE;

-- =========================
-- Performance Analysis
-- =========================

-- Analyze the yearly performance of products by comparing their sales to both 
-- the average sales performance of the product and the previous years's sales

WITH CTE AS (
	SELECT DISTINCT
		  dp.product_name
		, YEAR(fs.order_date) AS order_year
		, SUM(fs.sales_amount) AS product_yearly_sales
	FROM gold.fact_sales fs
	LEFT JOIN gold.dim_products dp
		ON fs.product_key = dp.product_key
	WHERE fs.order_date IS NOT NULL
	GROUP BY 
		  YEAR(fs.order_date)
		, dp.product_name
)
SELECT
	  product_name
	, order_year
	, product_yearly_sales
	, AVG(product_yearly_sales) OVER (PARTITION BY product_name) as product_average_sales
	, product_yearly_sales - AVG(product_yearly_sales) OVER (PARTITION BY product_name) AS avg_diff
	, CASE 
			WHEN product_yearly_sales - AVG(product_yearly_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above Avg'
			WHEN product_yearly_sales - AVG(product_yearly_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below Avg'
			ELSE 'Avg'
	  END AS Avg_Change
	-- Year-over-year Analysis
	, LAG(product_yearly_sales) OVER (PARTITION BY product_name ORDER BY order_year) as previous_year_sales
	, product_yearly_sales - LAG(product_yearly_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS previous_diff
	, CASE 
			WHEN product_yearly_sales - LAG(product_yearly_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Above Previous Year'
			WHEN product_yearly_sales - LAG(product_yearly_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Below Previous Year'
			ELSE 'No Change'
	  END AS Previous_Change
FROM CTE
ORDER BY product_name, order_year;

-- ==========================
-- Part-to-Whole Analysis
-- ==========================

WITH CTE AS (
	SELECT DISTINCT
		  dp.category
		, SUM(fs.sales_amount) AS product_sales
	FROM gold.fact_sales fs
	LEFT JOIN gold.dim_products dp
		ON fs.product_key = dp.product_key
	WHERE fs.order_date IS NOT NULL
	GROUP BY dp.category
)
SELECT 
	  category
	, product_sales
	, SUM(product_sales) OVER () AS total_sales
	, CONCAT(ROUND((CAST(product_sales AS FLOAT) / SUM(product_sales) OVER ()) * 100,2),' %') AS percentage_contribution
FROM CTE
ORDER BY product_sales DESC;

-- ====================
-- Data Segmentation
-- ====================

-- Segment products into cost ranges and
-- count how many products fall into each segment

WITH CTE AS (
	SELECT 
		  product_name
		, CASE
			WHEN cost < 100 THEN 'Below 100' 
			WHEN cost <= 500 THEN '100-500'
			WHEN cost <= 1000 THEN '500-1000'
			ELSE 'Above 1000' 
		  END AS cost_range
	FROM gold.dim_products
)
SELECT
	cost_range
	, COUNT(product_name) total_products
FROM CTE
GROUP BY cost_range
ORDER BY cost_range;

/* Group customers into three segments based on their spending behaviour:
	- VIP: Customers with at least 12 months of history and spending more than 5000.
	- Regular: Customers with at least 12 months of history and spending 5000 or less.
	- New: Customers with a lifespan less than 12 months.
And find the total number of customers by each group */

WITH CTE AS (
SELECT
	  dc.customer_key
	, DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
	, SUM(sales_amount) AS total_spend
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc
	ON fs.customer_key = dc.customer_key
GROUP BY dc.customer_key
)
SELECT 
	  segments
	, COUNT(DISTINCT customer_key) AS customer_count
FROM (
	SELECT 
		  customer_key
		, CASE 
			WHEN lifespan >= 12 AND total_spend > 5000 THEN 'VIP'
			WHEN lifespan >= 12 AND total_spend <= 5000 THEN 'Regular'
			ELSE 'NEW'
		  END AS segments
	FROM CTE
) t
GROUP BY segments
ORDER BY customer_count DESC;


