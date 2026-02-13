/* =========================================================
   PROJECT: Logistics Optimization for Delivery Routes (UPS)
   DATABASE: ups_logistics
   AUTHOR: Manas Patnaik
   DESCRIPTION:
   SQL-based analysis to clean data, analyze delivery delays,
   optimize routes, and evaluate warehouse & agent performance.
   ========================================================= */
  
   USE ups_logistics;
   
-- =========================================================
-- TASK 1: DATA CLEANING & PREPARATION
-- =========================================================

/* ---------------------------------------------------------
   1.1 Duplicate Order_ID Check
   Purpose: Ensure each order is unique before analysis
---------------------------------------------------------- */

SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT Order_ID) AS unique_orders
FROM orders;

/*
Observation:
- total_rows = unique_orders
- No duplicate Order_ID records found
*/

/* ---------------------------------------------------------
   1.2 Traffic Delay Null Check (Routes Table)
   Purpose: Verify completeness of Traffic_Delay_Min
---------------------------------------------------------- */

SELECT COUNT(*) AS total_routes,
       COUNT(Traffic_Delay_Min) AS non_null_delay
FROM routes;

/*
Observation:
- No NULL values found in Traffic_Delay_Min
- No replacement required
*/

/* ---------------------------------------------------------
   1.3 Date Format Standardization
   Purpose: Convert text-based date columns to DATE format
---------------------------------------------------------- */

ALTER TABLE orders
MODIFY Order_Date DATE,
MODIFY Expected_Delivery_Date DATE,
MODIFY Actual_Delivery_Date DATE;

ALTER TABLE shipment_tracking
MODIFY Checkpoint_Time DATE;

/*
Result:
- All date columns standardized to YYYY-MM-DD
*/

/* ---------------------------------------------------------
   1.4 Invalid Delivery Date Flagging
   Purpose: Identify records where delivery date < order date
---------------------------------------------------------- */

SELECT 
    Order_ID,
    Order_Date,
    Actual_Delivery_Date,
    CASE 
        WHEN Actual_Delivery_Date < Order_Date 
        THEN 'INVALID_RECORD'
        ELSE 'VALID_RECORD'
    END AS Record_Status
FROM orders;

/*
Observation:
- No invalid records found
*/

-- =========================================================
-- TASK 2: DELIVERY DELAY ANALYSIS
-- =========================================================

/* ---------------------------------------------------------
   2.1 Delivery Delay Calculation
   Purpose: Calculate delivery delay (in days) for each order
            based on expected vs actual delivery dates
--------------------------------------------------------- */

SELECT
    Order_ID,
    Route_ID,
    Warehouse_ID,
    Expected_Delivery_Date,
    Actual_Delivery_Date,
    GREATEST(
        DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date),
        0
    ) AS Delivery_Delay_Days
FROM orders;

/* 
   Observation:
   - Delivery delay calculated in days for each order
   - Early or on-time deliveries assigned a delay of 0 days
*/

/* ---------------------------------------------------------
   2.2 Top 10 Delayed Routes
   Purpose: Identify routes with highest average delivery delay
--------------------------------------------------------- */

SELECT
    Route_ID,
    ROUND(
        AVG(DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date)),
        2
    ) AS Avg_Delay_Days
FROM orders
WHERE Actual_Delivery_Date > Expected_Delivery_Date
GROUP BY Route_ID
ORDER BY Avg_Delay_Days DESC
LIMIT 10;

/* 
   Observation:
   - Routes ranked based on average delivery delay
   - Top 10 consistently underperforming routes identified
*/

/* ---------------------------------------------------------
   2.3 Warehouse-wise Delay Ranking
   Purpose: Rank orders by delivery delay within each warehouse
--------------------------------------------------------- */

SELECT
    Order_ID,
    Warehouse_ID,
    Route_ID,
    GREATEST(
        DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date),
        0
    ) AS Delivery_Delay_Days,
    RANK() OVER (
        PARTITION BY Warehouse_ID
        ORDER BY 
            GREATEST(
                DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date),
                0
            ) DESC
    ) AS Delay_Rank_In_Warehouse
FROM orders;

/* 
   Observation:
   - Orders ranked based on delay within each warehouse
   - Window function enables localized performance analysis
*/

/* =========================================================
   TASK 3: Route Optimization Insights
   ========================================================= */

/* ---------------------------------------------------------
   3.1 Route-Level Performance Metrics
   Purpose:
   - Calculate average delivery time
   - Calculate average traffic delay
   - Compute distance-to-time efficiency for each route
   --------------------------------------------------------- */

SELECT
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    ROUND(
        AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)), 2
    ) AS Avg_Delivery_Time_Days,
    r.Traffic_Delay_Min AS Avg_Traffic_Delay_Min,
    ROUND(
        r.Distance_KM / r.Average_Travel_Time_Min, 4
    ) AS Distance_Time_Efficiency
FROM routes r
JOIN orders o
    ON r.Route_ID = o.Route_ID
GROUP BY
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    r.Distance_KM,
    r.Average_Travel_Time_Min,
    r.Traffic_Delay_Min;

/* ---------------------------------------------------------
   3.2 Routes with Worst Efficiency Ratio
   Purpose:
   - Identify 3 least efficient routes based on
     distance-to-time efficiency
   --------------------------------------------------------- */

SELECT
    Route_ID,
    Start_Location,
    End_Location,
    ROUND(
        Distance_KM / Average_Travel_Time_Min, 4
    ) AS Distance_Time_Efficiency
FROM routes
ORDER BY Distance_Time_Efficiency ASC
LIMIT 3;

/*
Observation:
- These routes take longer time per kilometer travelled
- Indicates congestion, poor infrastructure, or planning issues
- High potential for optimization
*/

/* ---------------------------------------------------------
   3.3 Routes with More Than 20% Delayed Shipments
   Purpose:
   - Identify routes where delayed deliveries exceed 20%
   --------------------------------------------------------- */

SELECT
    Route_ID,
    COUNT(*) AS Total_Orders,
    SUM(
        CASE
            WHEN Delivery_Status = 'Delayed' THEN 1
            ELSE 0
        END
    ) AS Delayed_Orders,
    ROUND(
        (
            SUM(
                CASE
                    WHEN Delivery_Status = 'Delayed' THEN 1
                    ELSE 0
                END
            ) * 100.0
        ) / COUNT(*),
        2
    ) AS Delay_Percentage
FROM orders
GROUP BY Route_ID
HAVING Delay_Percentage > 20;

/*
Observation:
- Routes with more than 20% delayed orders identified
- Indicates consistent delivery reliability issues
- These routes require priority optimization
*/

/* ---------------------------------------------------------
   Final Recommendation:
   - Optimize routes with low efficiency ratios
   - Re-evaluate transit time estimates for high-delay routes
   - Consider alternate paths or delivery time windows
   - Assign experienced delivery agents to critical routes
   --------------------------------------------------------- */
   
-- =========================================================
-- TASK 4: WAREHOUSE PERFORMANCE
-- =========================================================

/* ---------------------------------------------------------
   4.1 Top 3 Warehouses by Highest Average Processing Time
   Purpose:
   - Identify warehouses causing maximum internal delays
   --------------------------------------------------------- */

SELECT
    Warehouse_ID,
    Location,
    Processing_Time_Min
FROM warehouses
ORDER BY Processing_Time_Min DESC
LIMIT 3;

/*
Observation:
- Warehouses with highest processing times identified
- These locations are potential operational bottlenecks
- High processing time directly impacts delivery delays
*/

/* ---------------------------------------------------------
   4.2 Total vs Delayed Shipments per Warehouse
   Purpose:
   - Compare shipment volume with delayed deliveries
   --------------------------------------------------------- */

SELECT
    Warehouse_ID,
    COUNT(*) AS Total_Orders,
    SUM(
        CASE
            WHEN Delivery_Status = 'Delayed' THEN 1
            ELSE 0
        END
    ) AS Delayed_Orders
FROM orders
GROUP BY Warehouse_ID;

/*
Observation:
- Shows workload handled by each warehouse
- Highlights warehouses contributing most to delayed orders
- Helps prioritize operational improvements
*/

/* ---------------------------------------------------------
   4.3 Bottleneck Warehouses Using CTE
   Purpose:
   - Identify warehouses with processing time
     greater than global average
   --------------------------------------------------------- */

WITH Avg_Processing_Time AS (
    SELECT
        AVG(Processing_Time_Min) AS Global_Avg_Time
    FROM warehouses
)
SELECT
    w.Warehouse_ID,
    w.Location,
    w.Processing_Time_Min
FROM warehouses w
JOIN Avg_Processing_Time a
    ON w.Processing_Time_Min > a.Global_Avg_Time;

/*
Observation:
- Warehouses exceeding global average processing time identified
- These are system-wide bottlenecks
- Improvement here yields maximum performance gains
*/

/* ---------------------------------------------------------
   4.4 Rank Warehouses by On-Time Delivery Percentage
   Purpose:
   - Evaluate delivery reliability per warehouse
   --------------------------------------------------------- */

SELECT
    Warehouse_ID,
    ROUND(
        SUM(
            CASE
                WHEN Delivery_Status = 'On Time' THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS On_Time_Delivery_Percentage,
    RANK() OVER (
        ORDER BY
            SUM(
                CASE
                    WHEN Delivery_Status = 'On Time' THEN 1
                    ELSE 0
                END
            ) * 100.0 / COUNT(*) DESC
    ) AS Warehouse_Rank
FROM orders
GROUP BY Warehouse_ID;

/*
Observation:
- Warehouses ranked based on delivery reliability
- Higher rank indicates better on-time performance
- Supports data-driven warehouse benchmarking
*/

-- =========================================================
-- TASK 5: DELIVERY AGENT PERFORMANCE
-- =========================================================

/* ---------------------------------------------------------
   5.1 Rank Delivery Agents per Route by On-Time Percentage
   Purpose:
   - Identify best and worst performing agents on each route
   --------------------------------------------------------- */

SELECT
    Agent_ID,
    Route_ID,
    On_Time_Percentage,
    RANK() OVER (
        PARTITION BY Route_ID
        ORDER BY On_Time_Percentage DESC
    ) AS Agent_Rank_On_Route
FROM delivery_agents;

/*
Observation:
- Agents ranked within each route based on delivery reliability
- Rank 1 agents are the most reliable on their respective routes
- Enables route-level performance comparison
*/

/* ---------------------------------------------------------
   5.2 Agents with On-Time Percentage Below 80%
   Purpose:
   - Identify underperforming delivery agents
   --------------------------------------------------------- */

SELECT
    Agent_ID,
    Route_ID,
    On_Time_Percentage
FROM delivery_agents
WHERE On_Time_Percentage < 80
ORDER BY On_Time_Percentage ASC;

/*
Observation:
- Agents with on-time delivery below 80% identified
- Indicates need for training or reassignment
- Helps improve overall delivery performance
*/

/* ---------------------------------------------------------
   5.3 Compare Average Speed of Top 5 vs Bottom 5 Agents
   Purpose:
   - Evaluate speed difference between high and low performers
   --------------------------------------------------------- */

SELECT
    'Top 5 Agents' AS Agent_Group,
    ROUND(AVG(Avg_Speed_KM_HR), 2) AS Avg_Speed
FROM (
    SELECT Avg_Speed_KM_HR
    FROM delivery_agents
    ORDER BY On_Time_Percentage DESC
    LIMIT 5
) AS Top_Agents

UNION ALL

SELECT
    'Bottom 5 Agents' AS Agent_Group,
    ROUND(AVG(Avg_Speed_KM_HR), 2) AS Avg_Speed
FROM (
    SELECT Avg_Speed_KM_HR
    FROM delivery_agents
    ORDER BY On_Time_Percentage ASC
    LIMIT 5
) AS Bottom_Agents;

/*
Observation:
- Top-performing agents have higher average speed
- Lower-speed agents correlate with poor on-time delivery
- Speed is a contributing factor to delivery performance
*/

-- =========================================================
-- TASK 6: SHIPMENT TRACKING ANALYTICS
-- =========================================================

/* ---------------------------------------------------------
   6.1 Last Checkpoint and Time for Each Order
   Purpose:
   - Identify the most recent checkpoint reached by each order
   --------------------------------------------------------- */

SELECT
    Order_ID,
    Checkpoint AS Last_Checkpoint,
    Checkpoint_Time AS Last_Checkpoint_Time
FROM (
    SELECT
        Order_ID,
        Checkpoint,
        Checkpoint_Time,
        ROW_NUMBER() OVER (
            PARTITION BY Order_ID
            ORDER BY Checkpoint_Time DESC
        ) AS rn
    FROM shipment_tracking
) t
WHERE rn = 1;

/*
Observation:
- Retrieves the latest checkpoint reached by each order
- Helps track shipment progress and identify stalled deliveries
*/

/* ---------------------------------------------------------
   6.2 Most Common Delay Reasons (Excluding 'None')
   Purpose:
   - Identify major causes of shipment delays
   --------------------------------------------------------- */

SELECT
    Delay_Reason,
    COUNT(*) AS Occurrence_Count
FROM shipment_tracking
WHERE Delay_Reason <> 'None'
GROUP BY Delay_Reason
ORDER BY Occurrence_Count DESC;

/*
Observation:
- Traffic and Weather emerge as dominant delay reasons
- Enables targeted corrective actions to reduce delays
*/

/* ---------------------------------------------------------
   6.3 Orders with More Than 2 Delayed Checkpoints
   Purpose:
   - Identify severely delayed shipments
   --------------------------------------------------------- */

SELECT
    Order_ID,
    COUNT(*) AS Delayed_Checkpoint_Count
FROM shipment_tracking
WHERE Delay_Reason <> 'None'
GROUP BY Order_ID
HAVING Delayed_Checkpoint_Count > 2;

/*
Observation:
- Orders with repeated delays identified
- Indicates high-risk shipments requiring intervention
*/

-- =========================================================
-- TASK 7: ADVANCED KPI REPORTING
-- =========================================================

/* ---------------------------------------------------------
   7.1 Average Delivery Delay per Region (Start_Location)
   Purpose:
   - Measure average delivery delay by route start location
   --------------------------------------------------------- */

SELECT
    r.Start_Location,
    ROUND(
        AVG(
            DATEDIFF(o.Actual_Delivery_Date, o.Expected_Delivery_Date)
        ),
        2
    ) AS Avg_Delivery_Delay_Days
FROM orders o
JOIN routes r
    ON o.Route_ID = r.Route_ID
WHERE o.Actual_Delivery_Date > o.Expected_Delivery_Date
GROUP BY r.Start_Location;

/*
Observation:
- Shows regions contributing most to delivery delays
- Helps prioritize regional-level logistics improvements
*/

/* ---------------------------------------------------------
   7.2 Overall On-Time Delivery Percentage
   Purpose:
   - Calculate delivery reliability KPI
   --------------------------------------------------------- */

SELECT
    ROUND(
        SUM(
            CASE
                WHEN Delivery_Status = 'On Time' THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS On_Time_Delivery_Percentage
FROM orders;

/*
Observation:
- Represents overall delivery reliability
- Higher percentage indicates better service performance
*/

/* ---------------------------------------------------------
   7.3 Average Traffic Delay per Route
   Purpose:
   - Identify routes impacted by traffic congestion
   --------------------------------------------------------- */

SELECT
    Route_ID,
    ROUND(AVG(Traffic_Delay_Min), 2) AS Avg_Traffic_Delay_Min
FROM routes
GROUP BY Route_ID;

/*
Observation:
- Highlights routes with consistently high traffic delays
- Supports route-level optimization decisions
*/

/* =========================================================
   FINAL CONCLUSION & RECOMMENDATIONS
   =========================================================

   Key Findings:
   - Several routes show consistently high traffic delays,
     directly impacting delivery timelines.
   - Overall on-time delivery performance indicates
     significant scope for operational improvement.
   - Certain warehouses act as processing bottlenecks,
     increasing downstream delivery delays.
   - Delivery agent performance varies notably across routes,
     with speed strongly correlated to on-time delivery.
   - Shipment tracking analysis highlights traffic, weather,
     and sorting as primary delay drivers.

   Recommendations:
   - Prioritize optimization of routes with low efficiency
     ratios and high traffic delays.
   - Improve processing efficiency at bottleneck warehouses
     through resource reallocation or process automation.
   - Provide targeted training or route reassignment for
     underperforming delivery agents.
   - Introduce proactive delay mitigation strategies for
     common delay reasons such as traffic and weather.
   - Use these KPIs as a continuous monitoring framework
     to track performance improvements over time.

   Business Impact:
   - Reduced delivery delays
   - Improved customer satisfaction
   - Lower operational and fuel costs
   - Data-driven decision making for logistics optimization

   ========================================================= */