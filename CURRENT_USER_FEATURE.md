# Current User Feature

## Overview
The app now supports a "current user" feature that automatically adds you to new splits, while still allowing flexibility for splitting bills where you weren't included.

## Key Features

### 1. **Automatic Inclusion**
- When you set someone as "This is me", they're automatically added to new splits
- Saves time since most people use the app to split their own bills

### 2. **"Add Me" Button**
- When a current user is set but not in the current split, an "Add Me" button appears
- Perfect for when you want to quickly add yourself to an existing split
- Located next to the "Add" button in the people management section

### 3. **Visual Indicator**
- Current user is marked with a "Me" badge in the people list
- Shows "Current User" label in the people picker

### 4. **Setting Current User**

#### First Time:
- When creating your first person, toggle "This is me" to ON
- This automatically enables for the first person if no current user exists

#### Changing Current User:
- In the people picker, swipe left on any person
- Tap "Set as Me" to make them the current user

### 5. **Flexibility for Group Splits**
- The current user feature doesn't interfere with splitting bills for groups you're not part of
- Simply remove yourself from the split or don't add yourself at all

## User Flow

### Common Case (You're on the bill):
1. Scan receipt
2. Your person is automatically added
3. Add others who shared the bill
4. Assign items

### Group Split (You're not on the bill):
1. Scan receipt  
2. Your person is automatically added
3. Remove yourself from the split (long press on your chip)
4. Add the people who were actually on the bill
5. Assign items

### Quick Add:
1. Already in a split without yourself
2. Tap "Add Me" button
3. You're instantly added to the split

## Technical Implementation

- Uses `@AppStorage("currentUserID")` to persist the current user preference
- `Person` model now has a unique `personID` field for reliable identification
- Current user is automatically added in `restorePeople()` for new splits
- Swipe gestures in people picker allow quick changing of current user

## Benefits

✅ Faster workflow for personal bill splitting  
✅ Still flexible for group scenarios  
✅ Clear visual feedback  
✅ Easy to change current user  
✅ No breaking changes to existing functionality
