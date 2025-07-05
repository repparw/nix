# ~/.config/nextcloud_tasks_cli.py
import asyncio
import sys
from datetime import datetime, timedelta, timezone
import re
import os
import uuid

import caldav
from icalendar import Calendar, vTodo, vText, vDatetime # Import vDatetime for proper time handling

# --- Configuration ---
# Your Nextcloud CalDAV tasks URL.
# This typically looks like: https://your-nextcloud-instance.com/remote.php/dav/calendars/YOUR_USERNAME/YOUR_TASK_LIST_NAME/
# You can often find this in your Nextcloud Calendar/Tasks settings when setting up a new CalDAV client.
# A common pattern is '/remote.php/dav/calendars/USERNAME/personal/' or '/remote.php/dav/calendars/USERNAME/tasks/'
CALDAV_URL = "https://leo.it.tab.digital/remote.php/dav/calendars/" # Base URL, will be completed with user/list
USERNAME = os.environ.get("NEXTCLOUD_USER") # Get from environment variable
PASSWORD = os.environ.get("NEXTCLOUD_PASSWORD") # Get from environment variable
DEFAULT_TASK_LIST_NAME = "personal" # Common default, adjust if your list is named differently (e.g., "tasks")
VERIFY_SSL = True # Set to False only if you have self-signed certs and know the risks

# --- Time parsing functions (same as before, but ensure timezone awareness for CalDAV) ---
def parse_time_string(time_str: str) -> datetime:
    # Use timezone-aware datetime objects for consistency with CalDAV
    now = datetime.now(timezone.utc).astimezone(datetime.now().astimezone().tzinfo) # Local timezone
    today_9am = now.replace(hour=9, minute=0, second=0, microsecond=0)
    today_evening = now.replace(hour=19, minute=0, second=0, microsecond=0)
    tomorrow_9am = today_9am + timedelta(days=1)

    time_str = time_str.lower().strip()

    if time_str == "morning":
        target_dt = today_9am
        if target_dt < now: target_dt += timedelta(days=1)
        return target_dt
    elif time_str == "evening":
        target_dt = today_evening
        if target_dt < now: target_dt += timedelta(days=1)
        return target_dt
    elif time_str == "tomorrow":
        return tomorrow_9am
    
    # Time delta: 1h, 1h30m, 2d
    time_delta_match = re.match(r'^(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$', time_str)
    if time_delta_match:
        days = int(time_delta_match.group(1) or 0)
        hours = int(time_delta_match.group(2) or 0)
        minutes = int(time_delta_match.group(3) or 0)
        seconds = int(time_delta_match.group(4) or 0)
        return now + timedelta(days=days, hours=hours, minutes=minutes, seconds=seconds)

    # Specific hour: 9, 21
    hour_match = re.match(r'^([0-9]|1[0-9]|2[0-3])$', time_str)
    if hour_match:
        target_hour = int(hour_match.group(1))
        target_time = now.replace(hour=target_hour, minute=0, second=0, microsecond=0)
        return target_time if target_time > now else target_time + timedelta(days=1) # If time passed, next day

    # Date and optional hour: 24.12 9, 24.12.2023, 24.12
    date_hour_match = re.match(r'^(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?\.?\s*(\d{1,2})?:?(\d{2})?$', time_str)
    if date_hour_match:
        day, month, year_str, hour_str, minute_str = date_hour_match.groups()
        day = int(day)
        month = int(month)
        year = int(year_str) if year_str else now.year
        hour = int(hour_str) if hour_str else 9 # Default to 9am
        minute = int(minute_str) if minute_str else 0

        # Handle partial year (e.g., 23 for 2023)
        if year < 100:
            year += 2000 if year <= (now.year % 100) + 10 else 1900 # Heuristic for future dates

        try:
            target_dt = datetime(year, month, day, hour, minute, 0, tzinfo=now.tzinfo) # Make it timezone aware
            # If date is in the past, assume next year (for recurring annual dates)
            if target_dt < now and not (hour_str or minute_str): # Only for full dates without specific time
                target_dt = target_dt.replace(year=target_dt.year + 1)
            return target_dt
        except ValueError:
            pass # Fall through to default if date is invalid

    return now + timedelta(minutes=30) # Default if parsing fails or no time given

async def main():
    if not USERNAME or not PASSWORD:
        print("Error: NEXTCLOUD_USER and NEXTCLOUD_PASSWORD environment variables must be set.", file=sys.stderr)
        sys.exit(1)

    task_summary = sys.argv[1]
    due_date_str = None
    if len(sys.argv) > 2:
        due_date_str = sys.argv[2]
    
    due_datetime_obj = None
    if due_date_str:
        try:
            due_datetime_obj = parse_time_string(due_date_str)
        except Exception as e:
            print(f"Warning: Could not parse time '{due_date_str}'. Task will be created without a due date. Error: {e}", file=sys.stderr)

    client_url = CALDAV_URL
    # Nextcloud CalDAV URLs are typically structured as:
    # BASE_URL/remote.php/dav/calendars/USERNAME/TASK_LIST_NAME/
    
    try:
        # Initialize CalDAV client
        client = caldav.DAVClient(
            url=client_url,
            username=USERNAME,
            password=PASSWORD,
            # verify_ssl=VERIFY_SSL # caldav library handles this via requests, can pass verify=VERIFY_SSL to requests session
        )

        principal = client.principal()
        
        # Find the correct calendar (task list)
        target_calendar = None
        for calendar in await principal.calendars():
            # The .name property from caldav library should match Nextcloud's display name
            # or you might need to inspect calendar.url to match the path component
            if calendar.name and calendar.name.lower() == DEFAULT_TASK_LIST_NAME.lower():
                target_calendar = calendar
                break
            # Fallback if name isn't reliably available, try to match by URL path
            if DEFAULT_TASK_LIST_NAME.lower() in str(calendar.url).lower():
                 target_calendar = calendar
                 break


        if not target_calendar:
            print(f"Error: Task list '{DEFAULT_TASK_LIST_NAME}' not found for user '{USERNAME}'. "
                  "Please check the list name and ensure the URL prefix is correct.", file=sys.stderr)
            print(f"Available calendars for '{USERNAME}':", file=sys.stderr)
            async for c in principal.calendars():
                print(f"- Name: {c.name}, URL: {c.url}", file=sys.stderr)
            sys.exit(1)

        # Create the iCalendar VTODO component
        todo = vTodo()
        todo.add('summary', vText(task_summary))
        todo.add('uid', str(uuid.uuid4())) # Unique identifier for the task
        todo.add('dtstamp', vDatetime(datetime.now(timezone.utc))) # Timestamp of creation in UTC

        if due_datetime_obj:
            # CalDAV tasks use DUE property for due dates
            # Ensure the datetime is in UTC for CalDAV standard if not an all-day event
            # For simplicity, we're converting to UTC directly here for DUE.
            todo.add('due', vDatetime(due_datetime_obj.astimezone(timezone.utc)))
            # Optional: Add DTSTART if you want the task to also appear in calendars starting at that time
            # todo.add('dtstart', vDatetime(due_datetime_obj.astimezone(timezone.utc)))
        
        # Nextcloud Tasks app typically renders a task if it has a SUMMARY and a UID.
        # It also implicitly sets STATUS:NEEDS-ACTION unless specified.
        # You could explicitly add: todo.add('status', 'NEEDS-ACTION')

        # Save the task to the calendar
        new_task_url = await target_calendar.save_todo(todo)
        
        due_display = f" @ {due_datetime_obj.strftime('%Y-%m-%d %H:%M')}" if due_datetime_obj else ""
        print(f"Task '{task_summary}' created successfully in '{target_calendar.name}'{due_display}!")
        sys.exit(0)

    except caldav.lib.error.NotFoundError as e:
        print(f"Error: CalDAV URL or calendar not found. Check CALDAV_URL and DEFAULT_TASK_LIST_NAME. Details: {e}", file=sys.stderr)
        sys.exit(1)
    except caldav.lib.error.AuthError as e:
        print(f"Error: Authentication failed. Check NEXTCLOUD_USER and NEXTCLOUD_PASSWORD environment variables. Details: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python nextcloud_tasks_cli.py <task_summary> [due_time_string]", file=sys.stderr)
        print("Due time examples: morning, evening, tomorrow, 1h, 2d3h, 9, 21, 24.12, 24.12 9, 24.12.2023", file=sys.stderr)
        sys.exit(1)
    asyncio.run(main())
