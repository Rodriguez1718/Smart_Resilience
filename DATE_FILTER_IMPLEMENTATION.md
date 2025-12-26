# Date Filter Implementation Guide

## Overview
The admin dashboard reports section now includes a date filter that allows admins to select a specific date and view data relative to that date. The period selector (Week, Month, Year) works in conjunction with this date picker.

## How It Works

### State Management
- **`_selectedReportDate`**: Stores the admin's selected date (defaults to today)
- **`_selectedPeriod`**: Stores the selected period (Week, Month, or Year)

### Date Range Logic

The date filter uses the selected date as the **END DATE** of the report range, and calculates backwards based on the selected period:

#### **Week Period**
- **Selected Date**: Any day (e.g., December 25, 2025)
- **Start Date**: 6 days before the selected date
- **End Date**: The selected date (end of day, 23:59:59)
- **Example**: If you select Dec 25, you'll see data from Dec 19-25 (7 days total)

#### **Month Period**
- **Selected Date**: Any day in the month (e.g., December 25, 2025)
- **Start Date**: First day of that month (Dec 1, 2025)
- **End Date**: The selected date (end of day, 23:59:59)
- **Example**: If you select Dec 25, you'll see data from Dec 1-25

#### **Year Period**
- **Selected Date**: Any day in the year (e.g., December 25, 2025)
- **Start Date**: January 1 of that year
- **End Date**: The selected date (end of day, 23:59:59)
- **Example**: If you select Dec 25, you'll see data from Jan 1 - Dec 25

## UI Components

### Date Picker Button
Located at the top of the reports view, shows:
- Calendar icon
- Label: "Report End Date"
- Currently selected date in readable format (e.g., "December 25, 2025")
- Click to open the date picker

### Period Selector
Three toggle buttons below the date picker:
- **Week**: Last 7 days from selected date
- **Month**: Current month up to selected date
- **Year**: Current year up to selected date

## Implementation Details

### The `_getFilteredAlerts()` Method
```dart
List<PanicAlert> _getFilteredAlerts() {
  DateTime startDate;
  DateTime endDate;

  // Set end date to end of selected day
  endDate = DateTime(
    _selectedReportDate.year,
    _selectedReportDate.month,
    _selectedReportDate.day,
    23,
    59,
    59,
  );

  switch (_selectedPeriod) {
    case 'Week':
      // Start from selected date, go back 7 days
      startDate = _selectedReportDate.subtract(const Duration(days: 6));
      startDate = DateTime(startDate.year, startDate.month, startDate.day);
      break;
    case 'Month':
      // Start from first day of month containing selected date
      startDate = DateTime(_selectedReportDate.year, _selectedReportDate.month, 1);
      break;
    case 'Year':
      // Start from first day of year containing selected date
      startDate = DateTime(_selectedReportDate.year, 1, 1);
      break;
  }

  final startTimestamp = startDate.millisecondsSinceEpoch;
  final endTimestamp = endDate.millisecondsSinceEpoch;

  return _allAlerts.where((alert) {
    if (alert.timestamp == 0) return false;
    return alert.timestamp >= startTimestamp &&
        alert.timestamp <= endTimestamp;
  }).toList();
}
```

## User Workflow

1. **Admin navigates to Reports** by clicking the "Reports" button
2. **Sees the default view** with today's date selected
3. **Clicks the date picker button** to choose a different date
4. **Date range updates automatically** based on the selected period:
   - **Week** shows the last 7 days ending on selected date
   - **Month** shows from the 1st of the month to selected date
   - **Year** shows from January 1st to selected date
5. **All statistics and charts update** to reflect only data in the selected range

## Examples

### Scenario 1: Weekly Report for Last Week of December
- **Selected Date**: December 25, 2025
- **Period**: Week
- **Date Range**: December 19 - December 25, 2025
- **Shows**: Panic alerts from that 7-day period

### Scenario 2: Monthly Report for Current Month
- **Selected Date**: December 25, 2025
- **Period**: Month
- **Date Range**: December 1 - December 25, 2025
- **Shows**: All panic alerts since the start of December

### Scenario 3: Year-to-Date Report
- **Selected Date**: December 25, 2025
- **Period**: Year
- **Date Range**: January 1 - December 25, 2025
- **Shows**: All panic alerts from the entire year up to that date

## Key Features

✅ **Intuitive Date Selection**: Click button to open date picker
✅ **Flexible Period Options**: Week, Month, or Year views
✅ **Real-time Updates**: Statistics update instantly when date or period changes
✅ **Logical Date Range**: Selected date is always the END of the range
✅ **Debug Logging**: Console logs show exact timestamp ranges for troubleshooting
✅ **Past Data Only**: Can't select future dates (firstDate: 2020, lastDate: now)

## Modifying the Date Range Logic

If you want to change how dates work, modify the `_getFilteredAlerts()` method:
- To include the selected date as START instead of END: Change calculation in 'Week' case
- To use a different day count: Change `Duration(days: 6)` to your desired value
- To change the default date: Change `_selectedReportDate = DateTime.now();` in `initState()`
