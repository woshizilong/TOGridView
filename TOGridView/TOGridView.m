//
//  TOGridView.m
//
//  Copyright 2013 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "TOGridView.h"
#import "TOGridViewCell.h"
#import <QuartzCore/QuartzCore.h>

#define LONG_PRESS_TIME 0.4f

@interface TOGridView () {
    
    /* Store what protocol methods the delegate/dataSource implement to help reduce overhead involved with checking that at runtime */
    struct {
        unsigned int dataSourceNumberOfCells;
        unsigned int dataSourceCellForIndex;
        unsigned int dataSourceCanMoveCell;
        unsigned int dataSourceCanEditCell;
        
        unsigned int delegateSizeOfCells;
        unsigned int delegateNumberOfCellsPerRow;
        unsigned int delegateInnerPadding;
        unsigned int delegateDecorationView;
        unsigned int delegateHeightOfRows;
        unsigned int delegateOffsetOfCellInRow;
        unsigned int delegateDidTapCell;
        unsigned int delegateDidLongTapCell;
        unsigned int delegateDidMoveCell;
    } _gridViewFlags;
}

@property (nonatomic,assign) Class cellClass;           /* The class that is used to spawn cells */
  

@property (nonatomic,assign) NSRange visibleCellRange;  /* The range of cells visible now */
  
  /* Stores for cells in use, and ones in standby */
@property (nonatomic,strong) NSMutableArray *recycledCells;
@property (nonatomic,strong) NSMutableDictionary *visibleCells;
  
  /* Decoration views */
@property (nonatomic,strong) NSMutableSet *recyledDecorationViews;
@property (nonatomic,strong) NSMutableSet *visibleDecorationViews;
  
  /* An array of all cells, and whether they're selected or not */
@property (nonatomic,strong) NSMutableArray *selectedCells;

@property (nonatomic,assign) CGSize cellPaddingInset;  /* Padding of cells from edge of view */
@property (nonatomic,assign) CGSize cellSize;  /*Size of each cell (This will become the tappable region) */
  
@property (nonatomic,assign) NSInteger numberOfCells;  /* Number of cells in grid view */
@property (nonatomic,assign) NSInteger numberOfCellsPerRow; /* Number of cells per row */
  

@property (nonatomic,assign) NSInteger widthBetweenCells;  /* The width between cells on a single row */
@property (nonatomic,assign) NSInteger rowHeight; /* The height of each row (ie the height of each decoration view) */
  

@property (nonatomic,assign) NSInteger offsetFromHeader;    /* Y-position of where the first row starts, after the header */
@property (nonatomic,assign) NSInteger offsetOfCellsInRow;  /* Y-offset of cell, within the row */
  
/* The ImageViews to store the before and after snapshots */
@property (nonatomic,strong) UIImageView *beforeSnapshot, *afterSnapshot;
  
/* We keep track of the last index that fired a 'longPress' event so we know not to do the 'tapped' event when we press up. */
@property (nonatomic,assign) NSInteger longPressIndex;

/* Timer that times how long the user has been tapping down on a cell */
@property (nonatomic,strong) NSTimer *longPressTimer;

/* Display link Timer that fires at 60FPS to dynamically animate the scrollView */
@property (nonatomic,strong) NSTimer *dragScrollTimer;
  
/* The amount the offset of the scrollview is incremented on each call of the timer*/
@property (nonatomic,assign) CGFloat dragScrollBias;
  
/* While dragging a cell around, this keeps track of which other cell's area it's currently hovering over */
@property (nonatomic,assign) NSInteger cellIndexBeingDraggedOver;
  
/* The specific cell item that's being dragged by the user */
@property (nonatomic,strong) TOGridViewCell *cellBeingDragged;

/* The index of the cell being dragged */
@property (nonatomic,assign) NSInteger cellBeingDraggedIndex;

/* The co-ords of the user's fingers from the last touch event to update the drag cell while it's animating */
@property (nonatomic,assign) CGPoint cellDragPoint;
  
/* The distance between the cell's origin and the user's touch position */
@property (nonatomic,assign) CGSize draggedCellOffset;
  
/* Temporarily halt laying out cells if we need to do something manually that causes iOS to call 'layoutSubViews' */
@property (nonatomic,assign) __block BOOL pauseCellLayout;
  
/* If we need to perform an animation that may trigger the cross-fade animation, temporarily disable it here. */
@property (nonatomic,assign) __block BOOL pauseCrossFadeAnimation;

- (void)enumerateCellDictionary:(NSDictionary *)cellDictionary withBlock:(void (^)(NSInteger index, TOGridViewCell *cell))block;
- (void)updateVisibleCellKeysWithDictionary:(NSDictionary *)updatedCells;
- (void)resetCellMetrics;
- (void)layoutCells;
- (CGSize)contentSizeOfScrollView;
- (UIImage *)snapshotOfCellsInRect:(CGRect)rect;
- (void)invalidateVisibleCells;
- (void)fireDragTimer:(id)timer;
- (TOGridViewCell *)cellInTouch:(UITouch *)touch;
- (NSInteger)indexOfVisibleCell:(TOGridViewCell *)cell;
- (void)setCell:(TOGridViewCell*)cell atIndex:(NSInteger)index dragging:(BOOL)dragging animated:(BOOL)animated;
- (void)fireLongPressTimer:(NSTimer *)timer;
- (NSInteger)indexOfCellAtPoint:(CGPoint)point;
- (void)updateCellsLayoutWithDraggedCellAtPoint:(CGPoint)dragPanPoint;
- (void)cancelDraggingCell;

@end

@implementation TOGridView

#pragma mark -
#pragma mark View Management
- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        // Default configuration for the UIScrollView
        self.bounces                    = YES;
        self.scrollsToTop               = YES;
        self.backgroundColor            = [UIColor blackColor];
        self.scrollEnabled              = YES;
        self.alwaysBounceVertical       = YES;
        
        // Disable the ability to tap multiple cells at the same time. (Otherwise it gets REALLY messy)
        self.multipleTouchEnabled       = NO;
        self.exclusiveTouch             = YES;
        
        // The sets to handle the recycling and repurposing/reuse of cells
        self.recycledCells              = [NSMutableArray array];
        self.visibleCells               = [NSMutableDictionary dictionary];
        
        // The default class used to instantiate new cells
        self.cellClass                  = [TOGridViewCell class];
        
        // Default settings for when dragging cells near the boundaries of the grid view
        self.dragScrollBoundaryDistance = 60;
        self.dragScrollMaxVelocity      = 15;
        
        // Default state handling for touch events
        self.longPressIndex             = -1;
        self.cellIndexBeingDraggedOver  = -1;
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame withCellClass:(Class)cellClass
{
    if (self = [self initWithFrame:frame])
        [self registerCellClass:cellClass];
    
    return self;
}

- (void)registerCellClass:(Class)cellClass
{
    self.cellClass = cellClass;
}

/* Kickstart the loading of the cells when this view is added to the view hierarchy */
- (void)didMoveToSuperview
{
    [self reloadGrid];
}

- (void)dealloc
{
    /* General clean-up */
    self.recycledCells = nil;
    self.visibleCells = nil;
}

#pragma mark -
#pragma mark Set-up
- (void)reloadGrid
{
    /* Get the number of cells from the data source */
    if (_gridViewFlags.dataSourceNumberOfCells)
        self.numberOfCells = [self.dataSource numberOfCellsInGridView:self];
    
    /* Use the delegate+dataSource to set up the rendering logistics of the cells */
    [self resetCellMetrics];
    
    /* Set up an array to track the selected state of each cell */
    self.selectedCells = nil;
    self.selectedCells = [NSMutableArray arrayWithCapacity:self.numberOfCells];
  
    /* Remove any existing cells */
    [self invalidateVisibleCells];
    
    /* Perform a redraw operation */
    [self layoutCells];
}

- (void)resetCellMetrics
{
    /* Get outer padding of cells */
    if (_gridViewFlags.delegateInnerPadding)
        self.cellPaddingInset = [self.delegate innerPaddingForGridView:self];
    
    /* Grab the size of each cell */
    if (_gridViewFlags.delegateSizeOfCells)
        self.cellSize = [self.delegate sizeOfCellsForGridView:self];
    
    /* See if there is a custom height for each row of cells */
    if (_gridViewFlags.delegateHeightOfRows)
        self.rowHeight = [self.delegate heightOfRowsInGridView:self];
    else
        self.rowHeight = self.cellSize.height;
    
    /* See if there is a custom offset of cells from within each row */
    if (_gridViewFlags.delegateOffsetOfCellInRow)
        self.offsetOfCellsInRow = [self.delegate offsetOfCellsInRowsInGridView:self];
    
    /* Get the number of cells per row */
    if (_gridViewFlags.delegateNumberOfCellsPerRow)
        self.numberOfCellsPerRow = [self.delegate numberOfCellsPerRowForGridView:self];
    
    /* Work out the spacing between cells */
    self.widthBetweenCells = (NSInteger)floor(((CGRectGetWidth(self.bounds) - (self.cellPaddingInset.width*2)) //Overall width of row
                                           - (_cellSize.width * self.numberOfCellsPerRow)) //minus the combined width of all cells
                                          / (self.numberOfCellsPerRow-1)); //divided by the number of gaps between
    
    /* Set up the scrollview and the subsequent contentView */
    self.contentSize = [self contentSizeOfScrollView];
}

/* Take into account the offsets/header size/cell rows to cacluclate the total size of the scrollview */
- (CGSize)contentSizeOfScrollView
{
    CGSize size;
    
    size.width      = CGRectGetWidth(self.bounds);
    
    size.height     = self.offsetFromHeader;
    size.height     += self.cellPaddingInset.height * 2;
    
    if (self.numberOfCells)
        size.height += (NSInteger)(ceil((CGFloat)self.numberOfCells / (CGFloat)self.numberOfCellsPerRow) * self.rowHeight);
    
    return size;
}

/* The origin of each cell */
- (CGPoint)originOfCellAtIndex:(NSInteger)cellIndex
{
    CGPoint origin = CGPointZero;
    
    origin.y    =   self.offsetFromHeader;                   /* The height of the header view */
    origin.y    +=  self.offsetOfCellsInRow;                 /* Relative offset of the cell in each row */
    origin.y    +=  self.cellPaddingInset.height;            /* The inset padding arond the cells in the scrollview */
    origin.y    += (self.rowHeight * floor(cellIndex/self.numberOfCellsPerRow));
    
    origin.x    =  self.cellPaddingInset.width;
    origin.x    += ((cellIndex % self.numberOfCellsPerRow) * (self.cellSize.width+self.widthBetweenCells));
    
    return origin;
}

- (CGSize)sizeOfCellAtIndex:(NSInteger)cellIndex
{
    CGSize cellSize = self.cellSize;
    
    //if there's supposed to be NO padding between the edge of the view and the cell,
    //and this cell is short by uneven necessity of the number of cells per row
    //(eg, 1024/3 on iPad = 341.333333333 pixels per cell :S), pad it out
    if (self.cellPaddingInset.width <= 0.0f + FLT_EPSILON && (cellIndex+1) % self.numberOfCellsPerRow == 0)
    {        
        CGPoint org = [self originOfCellAtIndex:cellIndex];
        if (org.x + cellSize.width < CGRectGetWidth(self.bounds) + FLT_EPSILON)
            cellSize.width = CGRectGetWidth(self.bounds) - org.x;
    }
    
    return cellSize;
}

- (void)invalidateVisibleCells
{
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        [cell removeFromSuperview];
        [self.recycledCells addObject:cell];
    }];
    
    [self.visibleCells removeAllObjects];
}

- (NSInteger)indexOfVisibleCell:(TOGridViewCell *)cell
{
    __block NSInteger index = NSNotFound;
    [self.visibleCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, TOGridViewCell *visibleCell, BOOL *stop) {
        if (visibleCell == cell)
        {
            index = key.integerValue;
            *stop = YES;
        }
    }];
    
    return index;
}

//Work out which cells this point of space will technically belong to
- (NSInteger)indexOfCellAtPoint:(CGPoint)point
{
    //work out which row we're on
    NSInteger rowIndex      = floor((point.y - (self.offsetFromHeader + self.cellPaddingInset.height)) / self.rowHeight) * self.numberOfCellsPerRow;
    
    //work out which number on the row we are
    NSInteger columnIndex   = floor((point.x + self.cellPaddingInset.width) / CGRectGetWidth(self.bounds) * self.numberOfCellsPerRow);
    
    NSInteger index = rowIndex + columnIndex;
    index = MAX( -1, index); //if the number of cells is below the start, return -1
    index = MIN(self.numberOfCells-1, index); //cap it at the max number of cells
    
    //return the cell index
    return index;
}

#pragma mark -
#pragma mark Cell Management
- (void)enumerateCellDictionary:(NSDictionary *)cellDictionary withBlock:(void (^)(NSInteger index, TOGridViewCell *))block
{
    if (block == nil)
        return;
    
    [cellDictionary enumerateKeysAndObjectsWithOptions:0 usingBlock:^(NSNumber *key, TOGridViewCell *cell, BOOL *stop) {
        block(key.integerValue, cell);
    }];
}

- (void)updateVisibleCellKeysWithDictionary:(NSDictionary *)updatedCells
{
    //Make a copy off the main list to work off (So we don't overwrite older values as we go)
    NSDictionary *visibleCellsCopy = [self.visibleCells copy];
    
    [updatedCells enumerateKeysAndObjectsUsingBlock:^(NSNumber *oldKey, NSNumber *newKey, BOOL *stop) {
        TOGridViewCell *cell = visibleCellsCopy[oldKey];
        if (cell == nil)
            return;
        
        //flush the object out, regardless of key
        [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:cell]];
        
        //add it back in as the new one
        [self.visibleCells setObject:cell forKey:newKey];
    }];
}

- (TOGridViewCell *)cellForIndex:(NSInteger)index
{
    return [self.visibleCells objectForKey:@(index)];
}

- (NSRange)visibleCellRange
{
    NSRange visibleCellRange;
    
    //The official origin of the first row, accounting for the header size and outer padding
    NSInteger   rowOrigin           = self.offsetFromHeader + self.cellPaddingInset.height;
    CGFloat     contentOffsetY      = self.bounds.origin.y; //bounds.origin on a scrollview contains the best up-to-date contentOffset
    NSInteger   numberOfRows        = floor(self.numberOfCells / self.numberOfCellsPerRow);
    
    NSInteger   firstVisibleRow     = floor((contentOffsetY-rowOrigin) / self.rowHeight);
    NSInteger   lastVisibleRow      = floor(((contentOffsetY-rowOrigin)+CGRectGetHeight(self.bounds)) / self.rowHeight);
    
    //make sure there are actually some visible rows
    if (lastVisibleRow >= 0 && firstVisibleRow <= numberOfRows)
    {
        visibleCellRange.location  = MAX(0,firstVisibleRow) * self.numberOfCellsPerRow;
        visibleCellRange.length    = (((lastVisibleRow - MAX(0,firstVisibleRow))+1) * self.numberOfCellsPerRow);
        
        if (visibleCellRange.location + visibleCellRange.length >= self.numberOfCells)
            visibleCellRange.length = self.numberOfCells - visibleCellRange.location;
    }
    else
    {
        visibleCellRange.location = -1;
        visibleCellRange.length = 0;
    }
    
    return visibleCellRange;
}

/* layoutCells handles all of the recycling/dequeing of cells as the scrollview is scrolling */
- (void)layoutCells
{
    if (self.numberOfCells == 0 || self.pauseCellLayout)
        return;
    
    //work out the index range of which cells should be visible now
    self.visibleCellRange = [self visibleCellRange];
    
    //go through each visible cell and see if they've moved beyond the visible range
    NSSet *cellsToRecyle = [self.visibleCells keysOfEntriesWithOptions:0 passingTest:^BOOL(NSNumber *key, TOGridViewCell *cell, BOOL *stop) {
        NSInteger index = key.integerValue;
        
        if (NSLocationInRange(index, self.visibleCellRange) == NO)
        {
            [cell removeFromSuperview];
            [self.recycledCells addObject:cell];
            return YES;
        }
            
        return NO;
    }];
    [self.visibleCells removeObjectsForKeys:[cellsToRecyle allObjects]];
    
    /* Only proceed with the following code if the number of visible cells is lower than it should be. */
    /* This code produces the most latency, so minimizing its call frequency is critical */
    if ([self.visibleCells count] >= self.visibleCellRange.length)
        return;

    for (NSInteger i = 0; i < self.visibleCellRange.length; i++)
    {
        NSInteger index = self.visibleCellRange.location+i;
        
        TOGridViewCell *cell = [self cellForIndex:index];
        if (cell || self.cellIndexBeingDraggedOver == index) //if we already have a cell, or the user is currently dragging over a space for a cell
            continue;
        
        //Get the cell with its content setup from the dataSource
        cell = [self.dataSource gridView:self cellForIndex:index];
        
        cell.hidden = NO;
        [cell setHighlighted:NO animated:NO];
        
        //if the cell has been selected, highlight it
        if (self.editing && [self.selectedCells indexOfObject:@(index)] != NSNotFound)
            [cell setSelected:YES animated:NO];
        else
            [cell setSelected:NO animated:NO];
        
        //make sure the frame is still properly set
        CGRect cellFrame;
        cellFrame.origin = [self originOfCellAtIndex:index];
        cellFrame.size = [self sizeOfCellAtIndex:index];
        cell.frame = cellFrame;
        
        //add it to the visible objects set (It's already out of the recycled set at this point)
        [self.visibleCells setObject:cell forKey:@(index)];
        
        //Make sure the cell is inserted ABOVE any visible background view, but still BELOW the scroll indicator bar graphic.
        //(ie, we can't simply call 'addSubiew')
        if (cell.superview == nil)
        {
            if (self.backgroundView)
                [self insertSubview:cell aboveSubview:self.backgroundView];
            else
                [self insertSubview:cell atIndex:0];
        }
        else
            cell.hidden = NO;
    }
}

/* 
layoutSubviews is called automatically whenever the scrollView's contentOffset changes,
or when the parent view controller changes orientation.

This orientation animation technique is a modified version of one of the techniques that was 
presented at WWDC 2012 in the presentation 'Polishing Your Interface Rotations'. It's been designed
with the goal of handling everything from within the view itself, without requiring any additional work
on the view controller's behalf.

When the iOS device is physically rotated and the orientation change event fires, (Which is captured here by detecting
when a CAAnimation object has been applied to the 'bounds' property of the view), the view quickly renders 
the 'before' and 'after' arrangement of the cells to UIImageViews. It then hides the original cells, overlays both image
views over the top of the scrollview, and cross-fade animates between the two for the same duration as the rotation animation.
*/
- (void)layoutSubviews
{
    [super layoutSubviews];
    
    /* Apply the crossfade effect if this method is being called while there is a pending 'bounds' animation present. */
    /* Capture the 'before' state to UIImageView before we reposition all of the cells */
    CABasicAnimation *boundsAnimation = (CABasicAnimation *)[self.layer animationForKey:@"bounds"];
    if (boundsAnimation && self.pauseCrossFadeAnimation == NO)
    {
        //make a mutable copy of the bounds animation,
        //as we will need to change the 'from' state in a little while
        boundsAnimation = [boundsAnimation mutableCopy];
        [self.layer removeAnimationForKey:@"bounds"];
        
        //disable user interaction
        self.userInteractionEnabled = NO;
        
        //halt the scroll view if it's currently moving
        if (self.isDecelerating || self.isDragging)
        {
            CGPoint contentOffset = self.bounds.origin;
            
            if (contentOffset.y < 0) //reset back to 0 if it's rubber-banding at the top
                [self setContentOffset:CGPointZero animated:NO];
            else if (contentOffset.y > self.contentSize.height - CGRectGetHeight(self.bounds)) // reset if rubber-banding at the bottom
                [self setContentOffset:CGPointMake(0, self.contentSize.height - CGRectGetHeight(self.bounds)) animated:NO];
            else //just halt it where-ever it is right now.
                [self setContentOffset:contentOffset animated:NO];
        }
        
        //At this point, self.bounds is already the newly resized value.
        //The original bounds are still available as the 'before' value in the layer animation object
        CGRect beforeRect = [boundsAnimation.fromValue CGRectValue];
        self.beforeSnapshot = [[UIImageView alloc] initWithImage:[self snapshotOfCellsInRect:beforeRect]];
        
        //Save the current visible cells before we apply the rotation so we can re-align it afterwards
        NSRange visibleCells = self.visibleCellRange;
        CGFloat yOffsetFromTopOfRow = beforeRect.origin.y - (self.offsetFromHeader + self.cellPaddingInset.height + (floor(visibleCells.location/self.numberOfCellsPerRow) * self.rowHeight));
        
        //poll the delegate again to see if anything needs changing since the bounds have changed
        //(Also, by this point, [UIViewController interfaceOrientation] has updated to the new orientation too)
        [self resetCellMetrics];
        
        //manually set contentOffset's value based off bounds.
        //Not sure why, but if we don't do this, periodically, contentOffset resets to [0,0] (possibly as a result of the frame changing) and borks the animation :S
        if (self.contentSize.height - self.bounds.size.height >= beforeRect.origin.y)
            self.contentOffset = beforeRect.origin;
        
        /* 
         If the header view is completely hidden (ie, only cells), re-orient the scroll view so the same cells are
         onscreen in the new orientation
         */
        if (self.contentOffset.y - self.offsetFromHeader > 0.0f && yOffsetFromTopOfRow >= 0.0f && visibleCells.location >= self.numberOfCellsPerRow)
        {
            CGFloat y = self.offsetFromHeader + self.cellPaddingInset.height + (self.rowHeight * floor(visibleCells.location/self.numberOfCellsPerRow)) + yOffsetFromTopOfRow;
            y = MIN(self.contentSize.height - self.bounds.size.height, y);
            
            self.contentOffset = CGPointMake(0,y);
        }
            
        //remove all of the current cells so they can be reset in the next layout call
        [self invalidateVisibleCells];
    }
    
    //layout the cells (and if we are mid-orientation, this will add/remove any more cells as required)
    [self layoutCells];
    
    //set up the second half of the animation crossfade and then start the crossfade animation
    if (boundsAnimation && self.pauseCrossFadeAnimation == NO)
    {
        /*
            "bounds" stores the scroll offset in its 'origin' property, and the actual size of the view in the 'size' property.
            Since we DO want the view to animate resizing itself, but we DON'T want it to animate scrolling at the same time, we'll have
            to modify the animation properties (which is why we made a mutable copy above) and then re-insert it back in.
        */
        CGRect beforeRect = [boundsAnimation.fromValue CGRectValue];
        beforeRect.origin.y = self.bounds.origin.y; //set the before and after scrolloffsets to the same value
        boundsAnimation.fromValue = [NSValue valueWithCGRect:beforeRect];
        boundsAnimation.delegate = self;
        boundsAnimation.removedOnCompletion = YES;
        [self.layer addAnimation:boundsAnimation forKey:@"bounds"];
        
        //Bake the 'after' snapshot to the second imageView (only if we're a non-retina device) and get it ready for display
        self.afterSnapshot          = [[UIImageView alloc] initWithImage:[self snapshotOfCellsInRect:self.bounds]];
        self.afterSnapshot.alpha    = 1.0f;
        self.afterSnapshot.frame    = CGRectMake(CGRectGetMinX(self.frame), CGRectGetMinY(self.frame), CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
        [self.afterSnapshot.layer removeAllAnimations];

        //Get the 'before' snapshot ready
        self.beforeSnapshot.frame       = CGRectMake(CGRectGetMinX(self.frame), CGRectGetMinY(self.frame), CGRectGetWidth(self.beforeSnapshot.frame), CGRectGetHeight(self.beforeSnapshot.frame));
        self.beforeSnapshot.alpha       = 0.0f;
        [self.beforeSnapshot.layer removeAllAnimations];
        
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            //disable EVERY ANIMATION that may have been applied to each cell and its subviews in the interim.
            //(This includes content, background, and highlight views)
            [cell.layer removeAllAnimations];
            for (UIView *subview in cell.subviews)
                [subview.layer removeAllAnimations];

            cell.hidden = YES; //Hide all of the visible cells
        }];
        
        //add the 'before' snapshot (Turns out it's better performance to add it to our superview rather than as a subview)
        [self.superview insertSubview:self.beforeSnapshot aboveSubview:self];
        CABasicAnimation *opacity   = [CABasicAnimation animationWithKeyPath:@"opacity"];
        opacity.timingFunction      = boundsAnimation.timingFunction;
        opacity.fromValue           = [NSNumber numberWithFloat:1.0f];
        opacity.toValue             = [NSNumber numberWithFloat:0.0f];
        opacity.duration            = boundsAnimation.duration;
        [self.beforeSnapshot.layer addAnimation:opacity forKey:@"opacity"];
        
        //add the 'after' snapshot
        [self.superview insertSubview:self.afterSnapshot aboveSubview:self.beforeSnapshot];
        
        opacity                 = [CABasicAnimation animationWithKeyPath:@"opacity"];
        opacity.timingFunction  = boundsAnimation.timingFunction;
        opacity.fromValue       = [NSNumber numberWithFloat:0.0f];
        opacity.toValue         = [NSNumber numberWithFloat:1.0f];
        opacity.duration        = boundsAnimation.duration;
        [self.afterSnapshot.layer addAnimation:opacity forKey:@"opacity"];
    }
    
    /* Update the background view to stay in the background */
    if (self.backgroundView)
        self.backgroundView.frame = CGRectMake(0, self.bounds.origin.y, CGRectGetWidth(self.backgroundView.bounds), CGRectGetHeight(self.backgroundView.bounds));
}

/* CAAnimation Delegate */
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    /* 
     This delegate actually gets called about 3 times per animation. So only proceed when it's definitely finished up.
     I'm HOPING there's no way the system can terminate an animation mid-way and then not call the finished flag here. That would suck.
    */
    if (flag == NO)
        return;
    
    /* Remove the snapshots from the superview */
    if (self.beforeSnapshot ) { [self.beforeSnapshot removeFromSuperview]; self.beforeSnapshot = nil; }
    if (self.afterSnapshot )  { [self.afterSnapshot removeFromSuperview];  self.afterSnapshot  = nil; }
    
    /* Reset all of the visible cells to their default display state. */
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        cell.hidden = NO;
        cell.alpha = 1.0f;
    }];
    
    /* Re-enable user interaction */
    self.userInteractionEnabled = YES;
}

/* Returns a UIImage of all of the visible cells on screen baked into it. */
- (UIImage *)snapshotOfCellsInRect:(CGRect)rect
{
    UIImage *image = nil;
    
    /* 
     Depending on the number of cells visible at any given point, a noticable speed boost can be given to Retina
     devices if the images are rendered at non-Retina resolutions (Given how fast these things rotate, it's BARELY noticable)
     */
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, self.nonRetinaRenderContexts ? 1.0f : 0.0f);
    {
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            //Save/Restore the graphics states to reset the global translation for each cell
            CGContextSaveGState(context);
            {
                //As 'renderInContext' uses the calling CALayer's local co-ord space,
                //the cells need to be positioned in the canvas using Quartz's matrix translations.
                CGContextTranslateCTM( context, cell.frame.origin.x, (cell.frame.origin.y-CGRectGetMinY(rect)) );
                [cell.layer renderInContext:context];
            }
            CGContextRestoreGState(context);
        }];
        
        image = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
    
    return image;
}

- (void)updateCellsLayoutWithDraggedCellAtPoint:(CGPoint)dragPanPoint
{
    NSInteger currentlyDraggedOverIndex = [self indexOfCellAtPoint:dragPanPoint];
    if (currentlyDraggedOverIndex == self.cellIndexBeingDraggedOver || currentlyDraggedOverIndex == -1)
        return;
    
    //The direction and number of stops we just moved the cell (eg cell 0 to cell 2 is '2')
    NSInteger offset = -(self.cellIndexBeingDraggedOver - currentlyDraggedOverIndex);
    
    NSMutableDictionary *updatedCellKeys = [NSMutableDictionary dictionary];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        if (cell == self.cellBeingDragged)
            return;
        
        NSInteger newIndex = 0;
        
        //If the offset is positive, we dragged the cell forward
        BOOL found = NO;
        if (offset > 0)
        {
            if (index <= self.cellIndexBeingDraggedOver+offset && index > self.cellIndexBeingDraggedOver)
            {
                newIndex = index - 1;
                found = YES;
            }
        }
        else
        {
            if (index >= self.cellIndexBeingDraggedOver+offset && index < self.cellIndexBeingDraggedOver)
            {
                newIndex = index + 1;
                found = YES;
            }
        }
        
        //Ignore cells that don't need to animate
        if (found == NO)
            return;
        
        //add the new value to our update dictionary
        [updatedCellKeys setObject:@(newIndex) forKey:@(index)];
        
        //figure out the number of cells between the one being dragged and this one
        NSInteger delta = abs(newIndex - self.cellIndexBeingDraggedOver);
        
        //animate it with a slight delay depending on how far away it was from the origin, so it looks a little more fluid 
        [UIView animateWithDuration:0.25f delay:0.05f*delta options:UIViewAnimationOptionCurveEaseInOut animations:^{
            CGRect frame = cell.frame;
            CGFloat y = frame.origin.y;
            
            frame.origin = [self originOfCellAtIndex:newIndex];
            
            //if a cell is shifting lines, make sure it renders ABOVE any other cells
            if ((NSInteger)y != (NSInteger)frame.origin.y)
                [self insertSubview:cell belowSubview:self.cellBeingDragged];
            
            //if the grid view is having to do a small amount of cell padding (eg, if the width of each cell doesn't fit the screen properly)
            //reset the cell here
            frame.size = [self sizeOfCellAtIndex:newIndex];
            cell.frame = frame;
            
        } completion:nil];
    }];
    
    //overwrite the visible cells with the new cell values
    [self updateVisibleCellKeysWithDictionary:updatedCellKeys];
    
    self.cellIndexBeingDraggedOver = currentlyDraggedOverIndex;
}

- (void)scrollToCellAtIndex:(NSInteger)cellIndex toPosition:(TOGridViewScrollPosition)position animated:(BOOL)animated completed:(void (^)(void))completed
{
    CGPoint cellPosition = [self originOfCellAtIndex:cellIndex];
    CGFloat scrollPosition = 0.0f;
    
    switch (position)
    {
        case TOGridViewScrollPositionTop:
            scrollPosition = cellPosition.y;
            break;
        case TOGridViewScrollPositionMiddle:
            scrollPosition = cellPosition.y + floor(CGRectGetHeight(self.bounds) * 0.5f) + floor(self.cellSize.height*0.5f);
            break;
        case TOGridViewScrollPositionBottom:
            scrollPosition = (cellPosition.y + CGRectGetHeight(self.bounds)) - self.cellSize.height;
            break;
        default:
            break;
    }
    
    if (animated)
    {
        [UIView animateWithDuration:0.5f animations:^{
            self.contentOffset = CGPointMake(scrollPosition, 0.0f);
        } completion:^(BOOL finished) {
            if (completed)
                completed();
        }];
    }
    else
    {
        self.contentOffset = CGPointMake(scrollPosition, 0.0f);
        if (completed)
            completed();
    }
}

#pragma mark -
#pragma mark Cell/Decoration Recycling

/* Dequeue a recycled cell for reuse */
- (TOGridViewCell *)dequeReusableCell
{
    TOGridViewCell *cell = nil;
    
    //Grab a cell that was previously recycled
    if ([self.recycledCells count] > 0)
    {
        cell = [self.recycledCells objectAtIndex:0];
        [self.recycledCells removeObject:cell];
        return cell;
    }

    //If there are no cells available, create a new one and set it up
    cell = [[self.cellClass alloc] initWithFrame:CGRectMake(0, 0, self.cellSize.width, self.cellSize.height)];
    cell.frame = CGRectMake(0, 0, self.cellSize.width, self.cellSize.height);
    [cell setHighlighted:NO animated:NO];
    
    return cell;
}

- (UIView *)dequeueReusableDecorationView
{
    return nil;
}

#pragma mark -
#pragma mark Cell Edit Handling
- (BOOL)insertCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self insertCellsAtIndices:[NSArray arrayWithObject:[NSNumber numberWithInt:index]] animated:animated];
}

- (BOOL)insertCellsAtIndices:(NSArray *)indices animated:(BOOL)animated
{
    //Make sure that the dataSource has already updated the number of cells, or this will cause utter confusion.
    NSInteger newNumberOfCells = [self.dataSource numberOfCellsInGridView:self];
    if (newNumberOfCells < self.numberOfCells + [indices count])
        [NSException raise:@"Invalid dataSource!" format:@"Data source needs to be updated before new cells can be inserted. Number of cells was %d when it needed to be %d", self.numberOfCells, newNumberOfCells];
    
    //make the new number of cells formal now since we'll need it in a bunch of calculations below
    self.numberOfCells = newNumberOfCells;
    
    //increment each visible cell to the next index as necessary
    NSMutableDictionary *updatedCellKeys = [NSMutableDictionary dictionary];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        NSInteger cellIncrement = 0;
        for (NSNumber *number in indices)
        {
            if (index >= number.integerValue)
                cellIncrement++;
        }
      
        NSInteger newIndex = index + cellIncrement;
        [updatedCellKeys setObject:@(newIndex) forKey:@(index)];
        
        NSNumber *prevIndex = @(index);
        if ([self.selectedCells indexOfObject:prevIndex] != NSNotFound)
        {
            [self.selectedCells removeObject:prevIndex];
            [self.selectedCells addObject:@(index)];
        }
        
        //clean up from a potential previous insert animation
        cell.hidden = NO;
    }];
    [self updateVisibleCellKeysWithDictionary:updatedCellKeys];
    
    //animate all of the existing cells into place
    if (animated)
    {
        //disable cell layout for now
        self.pauseCellLayout = YES;
        
        //set up any new cells that will need to slide down into view
        NSRange newVisibleCells = [self visibleCellRange];
        
        //The next cell index below the old to use as the origin basis for all the new cells we create down there
        NSInteger originCell = (newVisibleCells.location-1);
        
        //Go through and create each new cell, with their new IDs but leave them in their previous position
        for (NSInteger i=newVisibleCells.length-1; i >= 0; i--)
        {
            NSInteger newIndex = newVisibleCells.location+i;
            if (newIndex < 0)
                continue;
            
            //Don't add a new one if it's a new one that will spawn later
            BOOL isNewCell = NO;
            for (NSNumber *index in indices)
            {
                if (newIndex == [index intValue])
                {
                    isNewCell = YES;
                    break;
                }
            }
            
            //add a new cell
            TOGridViewCell *newCell = [self cellForIndex:newIndex];
            if (newCell)
                continue;
            
            newCell         = [self.dataSource gridView:self cellForIndex:newIndex];
            CGRect frame    = newCell.frame;
            frame.origin    = [self originOfCellAtIndex:MAX(0,originCell--)];
            frame.size      = [self sizeOfCellAtIndex:newVisibleCells.location+i];
            newCell.frame   = frame;
            [self.visibleCells setObject:newCell forKey:@(newIndex)];
        
            [self addSubview:newCell];
            
            if (isNewCell)
                newCell.hidden = YES;
        }
        
        self.pauseCellLayout = NO;
        
        //animate them in order
        NSArray *keys = [self.visibleCells.allKeys sortedArrayUsingSelector:@selector(compare:)];
        
        [UIView animateWithDuration:0.2f delay:0.03f options:UIViewAnimationOptionCurveEaseInOut animations:^{
            
            for (NSNumber *key in keys)
            {
                NSInteger index = key.integerValue;
                TOGridViewCell *cell = self.visibleCells[key];
                
                CGRect frame    = cell.frame;
                frame.size      = [self sizeOfCellAtIndex:index];
                frame.origin    = [self originOfCellAtIndex:index];
                
                //if we're sliding down a row, bring this cell to the front so it displays over the others
                if ((NSInteger)frame.origin.y != (NSInteger)cell.frame.origin.y)
                    [self bringSubviewToFront:cell];
                
                cell.frame = frame;
            }
        } completion:^(BOOL finished) {
            
            for (NSNumber *number in indices)
            {
                NSInteger newIndex = [number integerValue];
               
                TOGridViewCell *cell = [self cellForIndex:newIndex];
                if (cell == nil)
                {
                    cell            = [self.dataSource gridView:self cellForIndex:newIndex];
                    
                    CGRect frame    = cell.frame;
                    frame.origin    = [self originOfCellAtIndex:newIndex];
                    frame.size      = [self sizeOfCellAtIndex:newIndex];
                    cell.frame      = frame;
                    
                    [self.visibleCells setObject:cell forKey:@(newIndex)];
                    [self addSubview:cell];
                }
                    
                //fade it in
                cell.hidden = NO;
                cell.alpha  = 0.0f;
                cell.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.5f, 0.5f);
                [UIView animateWithDuration:0.15f delay:0.0f options:UIViewAnimationOptionCurveEaseOut animations:^{
                    cell.alpha      = 1.0f;
                    cell.transform  = CGAffineTransformIdentity;
                } completion:nil];
            }
            
            //clean out the excess recycled cells
            NSInteger maxNumberOfCellsInScreen = ceil(CGRectGetHeight(self.bounds) / self.rowHeight) * self.numberOfCellsPerRow;
            NSInteger numberOfCells = [self.recycledCells count] + [self.visibleCells count];
            if (numberOfCells > maxNumberOfCellsInScreen && [self.visibleCells count] <= maxNumberOfCellsInScreen)
            {
                while (numberOfCells > maxNumberOfCellsInScreen)
                {
                    if ([self.recycledCells count] == 0)
                        break;
                    
                    TOGridViewCell *cell = [self.recycledCells objectAtIndex:0];
                    if (cell == nil)
                        continue;
                    
                    [self.recycledCells removeObject:cell];
                    cell = nil;
                    
                    numberOfCells--;
                }
            }
            
            //reset the size of the content view to account for the new cells
            self.contentSize = [self contentSizeOfScrollView];
        }];
    }
    else
    {
        //go through and reshuffle all of the current to their new locations
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            CGRect frame    = cell.frame;
            frame.size      = [self sizeOfCellAtIndex:index];
            frame.origin    = [self originOfCellAtIndex:index];
            cell.frame      = frame;
        }];
        
        [self layoutCells];

        self.contentSize = [self contentSizeOfScrollView];
    }
    
    return YES;
}

- (BOOL)deleteCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    return [self deleteCellsAtIndices:[NSArray arrayWithObject:[NSNumber numberWithInt:index]] animated:animated];
}

- (BOOL)deleteCellsAtIndices:(NSArray *)indices animated:(BOOL)animated
{
    if ([indices count] == 0)
        return YES;
 
    //cancel the cell dragging if it's active
    if (self.editing)
        [self cancelDraggingCell];
    
    //Hang onto the lowest cell necessary to animate all visible cells
    //This can either be the very lowest cell targeted for deletion, or simply the first visible cell on screen
    __block NSInteger firstCellToAnimate = self.numberOfCells;
    
    //Hang onto the final cell that will be animated after the offset is applied
    __block NSInteger lastVisibleCell = 0;
    
    //Make sure that the dataSource has already updated the number of cells, otherwise all our calculations below will break
    NSInteger newNumberOfCells = [self.dataSource numberOfCellsInGridView:self];
    if (newNumberOfCells > self.numberOfCells - [indices count])
        [NSException raise:@"Invalid dataSource!" format:@"Data source needs to be updated before cells can be deleted. Number of cells was %d when it needed to be %d", self.numberOfCells, newNumberOfCells];
    
    //make the new number of cells formal now since we'll need it in a bunch of calculations below
    self.numberOfCells = newNumberOfCells;
    
    //go through each cell and work out which cells-to-delete are visible.
    NSMutableArray *visibleCellsToDelete = [NSMutableArray array];
    for (NSNumber *number in indices)
    {
        NSInteger deleteIndex = [number integerValue];

        //remember the selected cell indices we need to delete
        [self.selectedCells removeObject:number];
        
        //if the cell is within the visible screen region, prep it for animation
        if (NSLocationInRange(deleteIndex, self.visibleCellRange))
        {
            TOGridViewCell *cell = [self cellForIndex:deleteIndex];
            if (cell == nil)
                continue;
            
            //reset its animation properties, just in case
            cell.alpha      = 1.0f;
            cell.transform  = CGAffineTransformIdentity;
            
            [visibleCellsToDelete addObject:cell];
        }
        
        if (deleteIndex <= firstCellToAnimate)
            firstCellToAnimate = deleteIndex;
    }
    
    //work out what the new index for each visible cell will be after the targeted cells have been deleted
    NSMutableDictionary *updatedCellKeys = [NSMutableDictionary dictionary];
    [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
        NSInteger offset = 0;
        for (NSNumber *number in indices)
        {
            if (index >= [number integerValue])
                offset++;
        }
        
        //Check to see if this cell is after the lowest cell in the deletion stack
        BOOL shouldAnimateFromFirstVisibleCell = (index == self.visibleCellRange.location) && index > firstCellToAnimate;
        
        //Set the new index for this cell after the targeted cells are removed around it.
        //cap it off at 0 (If it's negative, it's definitely going to get deleted) to prevent any strange wrapping
        NSInteger newIndex = MAX(0, index - offset);
        
        //note the cell that changed so we can update visibleCells once this loop is complete
        [updatedCellKeys setObject:@(newIndex) forKey:@(index)];
        
        //if this cell is selected, update its index in the selected array
        NSNumber *prevIndex = @(index);
        if ([self.selectedCells indexOfObject:prevIndex] != NSNotFound)
        {
            [self.selectedCells removeObject:prevIndex];
            [self.selectedCells addObject:@(newIndex)];
        }
        
        if (shouldAnimateFromFirstVisibleCell)
            firstCellToAnimate = newIndex;
        
        //hang onto the final cell to use as the origin if we need to requeue any cells to animate in
        if (index > lastVisibleCell)
            lastVisibleCell = newIndex;
        
        //just make sure we clean up from a previous animation
        cell.hidden = NO;
    }];
    
    //fade out all the cells
    if (animated)
    {
        //disable scrolling to allow this animation to complete
        [self setUserInteractionEnabled:NO];
        
        //halt animation
        CGPoint scrollPoint = self.contentOffset;
        [self setContentOffset:scrollPoint animated:NO];

        //stop 'layoutCells' from interacting with this (Since 'layoutSubviews' gets triggered by iOS everytime we add/remove a cell)
        self.pauseCellLayout = YES;
        
        //Animate each of the selected cells to fade out
        [UIView animateWithDuration:0.15f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
            for (TOGridViewCell *cell in visibleCellsToDelete)
            {
                cell.alpha = 0.0f;
                cell.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.5f, 0.5f);
            }
        } completion:^(BOOL done) {
            //once done, recycle each cell that was animated out and add it back to the pool
            for (TOGridViewCell *cell in visibleCellsToDelete)
            {
                //once animated out, recycle the cells
                [cell removeFromSuperview];
                
                //reset the cell
                cell.transform = CGAffineTransformIdentity;
                cell.alpha = 1.0f;
                [cell setSelected:NO animated:NO];
                
                //recycle the cell
                [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:cell]];
                [self.recycledCells addObject:cell];
            }
            
            //update the remaining cells with the new values
            [self updateVisibleCellKeysWithDictionary:updatedCellKeys];
            
            //Now that the cells are out of the hierarchy, re-calculate which cells should be visible on screen now
            NSRange newVisibleCells = [self visibleCellRange];
            //The next cell index below the old to use as the origin basis for all the new cells we create down there
            NSInteger originCell = (newVisibleCells.location+newVisibleCells.length);
            
            //Go through and create each new cell, with their new IDs but leave them in their previous position
            for (NSInteger i=0; i < newVisibleCells.length; i++)
            {
                NSInteger newIndex = newVisibleCells.location+i;
                
                TOGridViewCell *newCell = [self cellForIndex:newIndex];
                if (newCell)
                    continue;
                
                newCell         = [self.dataSource gridView:self cellForIndex:newIndex];
                CGRect frame    = newCell.frame;
                frame.origin    = [self originOfCellAtIndex:originCell++];
                frame.size      = [self sizeOfCellAtIndex:newVisibleCells.location+i];
                newCell.frame   = frame;
                [self.visibleCells setObject:newCell forKey:@(newIndex)];
                
                [self addSubview:newCell];
            }
            
            //find the FINAL cell index so we can clean up after all of the animations
            __block NSInteger finalCellIndex = 0;
            [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
                if (index > finalCellIndex)
                    finalCellIndex = index;
            }];
            
            //sort the visible cells into their respective order so we can sort it in the right order
            NSArray *sortedVisibleCellIndices = [[self.visibleCells allKeys] sortedArrayUsingSelector:@selector(compare:)];
            
            //reset the size of all of the remaining cells before they move
            NSInteger i = 0; //i is used to add a cascading delay in front of cells
            for (NSNumber *key in sortedVisibleCellIndices)
            {
                NSInteger index = key.integerValue;
                TOGridViewCell *cell = self.visibleCells[key];
                
                //change the size of the cell as necessary
                CGRect frame = cell.frame;
                frame.size = [self sizeOfCellAtIndex:index];
                cell.frame = frame;
  
                [cell setSelected:NO animated:NO];
                
                //change the origin
                CGPoint newOrigin = [self originOfCellAtIndex:index];
                if ((NSInteger)cell.frame.origin.y != (NSInteger)newOrigin.y)
                    [self bringSubviewToFront:cell];

                //if this cell is truly moving a sizable distance, add a delay to the animation
                //(Otherwise it'll look like cells down the page take longer to move than others)
                if ((NSInteger)cell.frame.origin.y != (NSInteger)newOrigin.y && (NSInteger)cell.frame.origin.x != (NSInteger)newOrigin.x)
                    i++;
                
                [UIView animateWithDuration:0.30f delay:i*0.03f options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    CGRect frame = cell.frame;
                    frame.origin = newOrigin;
                    
                    //cap how far it can move up so it doesn't just shoot off so quickly that it becomes invisible
                    if (CGRectGetMaxY(cell.frame) - (newOrigin.y+CGRectGetHeight(self.bounds)) > CGRectGetHeight(self.bounds))
                        frame.origin.y = CGRectGetMinY(cell.frame) - (CGRectGetHeight(self.bounds)+CGRectGetHeight(cell.frame));
                    
                    cell.frame = frame;
                } completion:^(BOOL finished) {
                    if (index != finalCellIndex)
                        return;
                    
                    //re-enable 'layoutCells'
                    self.pauseCellLayout = NO;
                    
                    //reset all of the cells
                    [self layoutCells];
                    
                    //clean out the excess recycled cells
                    NSInteger maxNumberOfCellsInScreen = ceil(CGRectGetHeight(self.bounds) / self.rowHeight) * self.numberOfCellsPerRow;
                    NSInteger numberOfCells = [self.recycledCells count] + [self.visibleCells count];
                    if (numberOfCells > maxNumberOfCellsInScreen && [self.visibleCells count] <= maxNumberOfCellsInScreen)
                    {
                        while (numberOfCells > maxNumberOfCellsInScreen)
                        {
                            if ([self.recycledCells count] == 0)
                                break;
                            
                            TOGridViewCell *cell = [self.recycledCells objectAtIndex:0];
                            if (cell == nil)
                                continue;
                            
                            [self.recycledCells removeObject:cell];
                            cell = nil;
                            
                            numberOfCells--;
                        }
                    }
                    
                    //reenable user interaction
                    [self setUserInteractionEnabled:YES];
                
                    self.pauseCrossFadeAnimation = YES;
                    [UIView animateWithDuration:0.30f animations:^{
                        self.contentSize = [self contentSizeOfScrollView];
                    } completion:^(BOOL finished) {
                        self.pauseCrossFadeAnimation = NO;
                    }];
                    
                }];
            }
        }];
    }
    else
    {
        //loop through all of the cells to delete and remove them
        for (TOGridViewCell *cell in visibleCellsToDelete)
        {
            [cell removeFromSuperview];
            [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:cell]];
            [self.recycledCells addObject:cell];
        }
        
        [self updateVisibleCellKeysWithDictionary:updatedCellKeys];
        
        //reposition all of the current cells with their new indices
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            cell.frame = (CGRect){[self originOfCellAtIndex:index], [self sizeOfCellAtIndex:index]};
        }];
    
        //reset the size of the content view to account for the new cells
        self.contentSize = [self contentSizeOfScrollView];
        
        //re-layout all of the cells and re-adding any new ones
        [self layoutCells];
    }
    
    return YES;
}

- (BOOL)reloadCellAtIndex:(NSInteger)index
{
    return [self reloadCellsAtIndices:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
}

- (BOOL)reloadCellsAtIndices:(NSArray *)indices
{
    if ([indices count] == 0)
        return YES;
    
    for (NSNumber *index in indices)
    {
        NSInteger cellIndex = [index integerValue];
        
        //if the cell isn't visisble, skip it
        TOGridViewCell *cell = [self cellForIndex:cellIndex];
        if (cell == nil)
            continue;
        
        CGRect frame = cell.frame;
        [cell removeFromSuperview];
        [self.visibleCells removeObjectForKey:@(cellIndex)];
        [self.recycledCells addObject:cell];
        cell = nil;
        
        cell = [self.dataSource gridView:self cellForIndex:cellIndex];
        cell.frame = frame;
        
        if (self.backgroundView)
            [self insertSubview:cell aboveSubview:self.backgroundView];
        else
            [self insertSubview:cell atIndex:0];
    }
    
    return YES;
}

/* This is called manually by the delegate object */
- (void)unhighlightCellAtIndex:(NSInteger)index animated:(BOOL)animated
{
    TOGridViewCell *cell = [self cellForIndex:index];
    if (cell)
        [cell setHighlighted:NO animated:animated];
}

/* Called every 1/60th of a second to animate the scroll view */
- (void)fireDragTimer:(id)timer
{
    CGPoint offset = self.contentOffset;
    offset.y += self.dragScrollBias; //Add the calculated scroll bias to the current scroll offset
    offset.y = MAX(0, offset.y); //Clamp the value so we can't accidentally scroll past the end of the content
    offset.y = MIN(self.contentSize.height - CGRectGetHeight(self.bounds), offset.y);
    self.contentOffset = offset;
    
    CGPoint adjustedDragPoint = self.cellDragPoint;
    adjustedDragPoint.y += self.contentOffset.y;
    [self updateCellsLayoutWithDraggedCellAtPoint:adjustedDragPoint];
    
    /* If we're dragging a cell, update its position inside the scrollView to stick to the user's finger. */
    /* We can't move the cell outside of this view since that kills the touch events. :( */
    /* We also can't simply add the bias like we did above since it introduces floating point noise (and the cell starts to move on its own on screen :( ) */
    if (self.cellBeingDragged)
    {
        CGPoint center = self.cellBeingDragged.center;
        center.y = self.cellDragPoint.y + self.contentOffset.y;
        self.cellBeingDragged.center = center;
    }
}

- (NSArray *)indicesOfSelectedCells
{
    return [NSArray arrayWithArray:self.selectedCells];
}

- (BOOL)selectCellAtIndex:(NSInteger)index
{
    return [self selectCellsAtIndices:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
}

- (BOOL)selectCellsAtIndices:(NSArray *)indices
{
    for (NSNumber *index in indices)
    {
        NSInteger cellIndex = [index integerValue];
        
        if ([self.selectedCells indexOfObject:[NSNumber numberWithInteger:cellIndex]] == NSNotFound)
            [self.selectedCells addObject:[NSNumber numberWithInteger:cellIndex]];
        
        //if the cell is visible on-screen, set its state to selected
        TOGridViewCell *cell = [self cellForIndex:cellIndex];
        if (cell)
            [cell setSelected:YES animated:NO];
    }
    
    return YES;
}

- (BOOL)deselectCellAtIndex:(NSInteger)index
{
    return [self deselectCellsAtIndices:[NSArray arrayWithObject:[NSNumber numberWithInteger:index]]];
}

- (BOOL)deselectCellsAtIndices:(NSArray *)indices
{
    for (NSNumber *index in indices)
    {
        NSInteger cellIndex = [index integerValue];
        
        //update the entry in the array to 'selected'
        [self.selectedCells removeObject:[NSNumber numberWithInteger:cellIndex]];
        
        //if the cell is visible on-screen, set its state to selected
        TOGridViewCell *cell = [self cellForIndex:cellIndex];
        if (cell)
            [cell setSelected:NO animated:NO];
    }
    
    return YES;
}

#pragma mark -
#pragma mark Cell Interactions Handler
- (TOGridViewCell *)cellInTouch:(UITouch *)touch
{
    //start off with the view we directly hit with the UITouch
    UIView *view = [touch view];
    
    //traverse hierarchy to see if we hit inside a cell
    TOGridViewCell *cell = nil;
    do
    {
        if ([view isKindOfClass:[TOGridViewCell class]])
        {
            cell = (TOGridViewCell *)view;
            break;
        }
    }
    while ((view = view.superview) != nil);
    
    return cell;
}

/* touchesBagan is initially called when we first touch this view on the screen. There is no delay. */
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    //reset the long press counter
    self.longPressIndex = -1;
    
    UITouch *touch = [touches anyObject];
    TOGridViewCell *cell = [self cellInTouch:touch];
    if (cell)
    {
        [cell setHighlighted:YES animated:NO];
        
        //if we're set up to receive a long-press tap event, fire the timer now
        if (self.dragging == NO && ((self.editing == NO && _gridViewFlags.delegateDidLongTapCell) || (self.editing && _gridViewFlags.dataSourceCanMoveCell)))
            self.longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_TIME target:self selector:@selector(fireLongPressTimer:) userInfo:touch repeats:NO];
    }
    
    [super touchesBegan:touches withEvent:event];
}

- (void)fireLongPressTimer:(NSTimer *)timer
{
    UITouch *touch = [timer userInfo];
    TOGridViewCell *cell = (TOGridViewCell *)[self cellInTouch:touch];
    NSInteger index = [self indexOfVisibleCell:cell];
    if (index == NSNotFound)
        return;
    
    if (self.editing == NO)
    {
        [self.delegate gridView:self didLongTapCellAtIndex:index];
        
        //let 'touchesEnded' know we already performed the event for this one
        self.longPressIndex = index;
    }
    else
    {
        BOOL canMove = [self.dataSource gridView:self canMoveCellAtIndex:index];
        if (canMove == NO)
            return;
        
        // Hang onto the cell
        self.cellBeingDragged = cell;
        self.cellBeingDraggedIndex = index;
        self.cellIndexBeingDraggedOver = index;
        
        //make the cell animate out slightly
        [self bringSubviewToFront:self.cellBeingDragged];
        [self setCell:self.cellBeingDragged atIndex:self.cellBeingDraggedIndex dragging:YES animated:YES];
        
        CGPoint pointInCell = [touch locationInView:cell];
        
        //set the anchor point
        cell.layer.anchorPoint = CGPointMake(pointInCell.x/CGRectGetWidth(cell.bounds), pointInCell.y/CGRectGetHeight(cell.bounds));
        cell.center = [touch locationInView:self];
        
        //disable the scrollView
        [self setScrollEnabled:NO];
    }
}

/* touchesMoved is called when we start panning around the view without releasing our finger */
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    
    if (self.editing && self.cellBeingDragged)
    {
        CGPoint panPoint = [touch locationInView:self];
        
        self.cellBeingDragged.center = CGPointMake(panPoint.x + self.draggedCellOffset.width, panPoint.y + self.draggedCellOffset.height);
        
        /* Update the cells behind the one being dragged with new positions */
        [self updateCellsLayoutWithDraggedCellAtPoint:panPoint];
        
        panPoint.y -= self.bounds.origin.y; //compensate for scroll offset
        panPoint.y = MAX(panPoint.y, 0); panPoint.y = MIN(panPoint.y, CGRectGetHeight(self.bounds)); //clamp to the outer bounds of the view
        
        //Save a copy of the translated point for the drag animation below
        self.cellDragPoint = panPoint;
        
        //Determine if the touch location is within the scroll boundaries at either the top or bottom
        if ((panPoint.y < self.dragScrollBoundaryDistance && self.contentOffset.y > 0.0f) ||
            (panPoint.y > CGRectGetHeight(self.bounds) - self.dragScrollBoundaryDistance && (self.contentOffset.y < self.contentSize.height - CGRectGetHeight(self.bounds))))
        {
            //Kickstart a timer that'll fire at 60FPS to dynamically animate the scrollview
            if (self.dragScrollTimer == nil)
                self.dragScrollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/60.0f target:self selector:@selector(fireDragTimer:) userInfo:nil repeats:YES];
            
            //If we're scrolling at the top
            if (panPoint.y < self.dragScrollBoundaryDistance)
                self.dragScrollBias = -(self.dragScrollMaxVelocity - ((self.dragScrollMaxVelocity/self.dragScrollBoundaryDistance) * panPoint.y));
            else if (panPoint.y > CGRectGetHeight(self.bounds) - self.dragScrollBoundaryDistance) //we're scrolling at the bottom
                self.dragScrollBias = ((panPoint.y - (CGRectGetHeight(self.bounds) - self.dragScrollBoundaryDistance)) / self.dragScrollBoundaryDistance) * self.dragScrollMaxVelocity;
        }
        
        //cancel the scrolling if we tap up, or move our fingers into the middle of the screen
        if ((panPoint.y>self.dragScrollBoundaryDistance && panPoint.y<CGRectGetHeight(self.bounds)-self.dragScrollBoundaryDistance))
        {
            [self.dragScrollTimer invalidate];
            self.dragScrollTimer = nil;
        }
    }
        
    [super touchesMoved:touches withEvent:event];
}

/* touchesEnded is called if the user releases their finger from the device without panning the scroll view (eg a discrete tap and release) */
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{ 
    UITouch *touch = [touches anyObject];
    
    //The cell under our finger
    TOGridViewCell *cell = [self cellInTouch:touch];
    
    //if we were animating the scroll view at the time, cancel it
    [self.dragScrollTimer invalidate];
    
    //if we WEREN'T in edit mode, fire the delegate to say we tapped this cell (But make sure this cell didn't already fire a long press event)
    if (self.editing == NO)
    {
        NSInteger index = [self indexOfVisibleCell:cell];
        
        if (cell && _gridViewFlags.delegateDidTapCell && index != self.longPressIndex)
            [self.delegate gridView:self didTapCellAtIndex:index];
    }
    else //if we WERE editing
    {
        //if there's no cell being dragged (ie, we just tapped a cell), set it to 'selected'
        if (self.cellBeingDragged == nil)
        {
            NSInteger index = [self indexOfVisibleCell:cell];
            
            //unhighlight it
            [cell setHighlighted:NO animated:NO];
            
            NSNumber *cellIndexNumber = [NSNumber numberWithInteger:index];
            
            //set it to be either selected or unselected
            if ([self.selectedCells indexOfObject:cellIndexNumber] == NSNotFound)
            {
                [cell setSelected:YES animated:NO];
                [self.selectedCells addObject:cellIndexNumber];
            }
            else
            {
                [cell setSelected:NO animated:NO];
                [self.selectedCells removeObject:cellIndexNumber];
            }
        }
        else //if there IS a cell being dragged about, handle that now
        {
            NSInteger previousIndex = self.cellBeingDraggedIndex;
            NSInteger newIndex = self.cellIndexBeingDraggedOver;
            
            if (_gridViewFlags.delegateDidMoveCell)
                [self.delegate gridView:self didMoveCellAtIndex:previousIndex toIndex:newIndex];
            
            //re-associate the cell with its new index
            [self.visibleCells removeObjectsForKeys:[self.visibleCells allKeysForObject:self.cellBeingDragged]];
            [self.visibleCells setObject:self.cellBeingDragged forKey:@(newIndex)];
            
            //Grab the frame, reset the anchor point back to default (Which changes the frame to compensate), and then reapply the frame
            CGRect frame = self.cellBeingDragged.frame;
            self.cellBeingDragged.layer.anchorPoint = CGPointMake(0.5f,0.5f);
            self.cellBeingDragged.frame = frame;
            
            //Temporarily revert the transformation back to default, and make sure to properly resize the cell
            //(In case it's slightly longer/shorter due to padding issues)
            CGAffineTransform transform = self.cellBeingDragged.transform;
            self.cellBeingDragged.transform = CGAffineTransformIdentity;
            
            frame = self.cellBeingDragged.frame;
            frame.size = [self sizeOfCellAtIndex:newIndex];

            self.cellBeingDragged.frame = frame;
            self.cellBeingDragged.transform = transform;
            
            //animate it zipping back, and deselecting
            [self setCell:self.cellBeingDragged atIndex:newIndex dragging:NO animated:YES];
            [self.cellBeingDragged setHighlighted:NO animated:YES];
            
            //reset the cell handle for next time
            self.cellBeingDragged = nil;
            self.cellIndexBeingDraggedOver = -1;
            
            //re-enable scrolling
            [self setScrollEnabled:YES];
        }
    }
    
    [self.longPressTimer invalidate];
    self.longPressTimer = nil;
    
    [super touchesEnded:touches withEvent:event];
}

/* touchesCancelled is usually called if the user tapped down, but then started scrolling the UIScrollView. (Or potentially, if the user rotates the device) */
/* This will relinquish any state control we had on any cells. */
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    //The cell that was under our finger at the time
    TOGridViewCell *cell = [self cellInTouch:[touches anyObject]];
    
    //if there was actually a cell, cancel its highlighted state
    if (cell)
        [cell setHighlighted:NO animated:NO];
    
    //If we were in the middle of dragging a cell, kill it
    if (self.editing && self.cellBeingDragged)
        [self cancelDraggingCell];
    
    [super touchesCancelled:touches withEvent:event];
}

- (void)cancelDraggingCell
{
    if (self.cellBeingDragged == nil)
        return;
    
    self.cellBeingDragged.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
    [self setCell:self.cellBeingDragged atIndex:self.cellBeingDraggedIndex dragging:NO animated:NO];
    self.cellBeingDragged = nil;
    
    self.cellIndexBeingDraggedOver = -1;
    
    [self setScrollEnabled:YES];
}

- (void)setCell:(TOGridViewCell *)cell atIndex:(NSInteger)index dragging:(BOOL)dragging animated:(BOOL)animated
{
    //The original transformation state and a slightly scaled version
    CGAffineTransform originTransform   = CGAffineTransformIdentity;
    CGAffineTransform destTransform     = CGAffineTransformScale(originTransform, 1.1f, 1.1f);
    
    //The original alpha (fully opaque) and slightly transparent
    CGFloat originAlpha = 1.0f;
    CGFloat destAlpha   = 0.6f;
    
    if (animated)
    {
        //Perform the animation
        [UIView animateWithDuration:0.20f delay:0.0f options:UIViewAnimationOptionCurveEaseOut animations:^{
            if (dragging)
            {
                cell.transform  = destTransform;
                cell.alpha      = destAlpha;
            }
            else
            {
                cell.transform  = originTransform;
                cell.alpha      = originAlpha;
                
                CGRect frame = cell.frame;
                frame.origin = [self originOfCellAtIndex:index];
                cell.frame = frame;
            }
        } completion:nil];
    }
    else
    {
        /* Set the new values */
        if (dragging)
        {
            cell.transform = destTransform;
            cell.alpha = destAlpha;
        }
        else
        {
            cell.transform = originTransform;
            cell.alpha = originAlpha;
            
            CGRect frame = cell.frame;
            frame.origin = [self originOfCellAtIndex:index];
            cell.frame = frame;
        }
    }
}

#pragma mark -
#pragma mark Accessors
- (void)setDelegate:(id<TOGridViewDelegate>)delegate
{
    if (self.delegate == delegate)
        return;
    
    [super setDelegate:delegate];
    
    //Update the flags with the state of the new delegate
    _gridViewFlags.delegateDecorationView       = [self.delegate respondsToSelector:@selector(gridView:decorationViewForRowWithIndex:)];
    _gridViewFlags.delegateInnerPadding         = [self.delegate respondsToSelector:@selector(innerPaddingForGridView:)];
    _gridViewFlags.delegateNumberOfCellsPerRow  = [self.delegate respondsToSelector:@selector(numberOfCellsPerRowForGridView:)];
    _gridViewFlags.delegateSizeOfCells          = [self.delegate respondsToSelector:@selector(sizeOfCellsForGridView:)];
    _gridViewFlags.delegateHeightOfRows         = [self.delegate respondsToSelector:@selector(heightOfRowsInGridView:)];
    _gridViewFlags.delegateDidLongTapCell       = [self.delegate respondsToSelector:@selector(gridView:didLongTapCellAtIndex:)];
    _gridViewFlags.delegateDidTapCell           = [self.delegate respondsToSelector:@selector(gridView:didTapCellAtIndex:)];
    _gridViewFlags.delegateDidMoveCell          = [self.delegate respondsToSelector:@selector(gridView:didMoveCellAtIndex:toIndex:)];
}

- (void)setDataSource:(id<TOGridViewDataSource>)dataSource
{
    if (self.dataSource == dataSource)
        return;
    
    _dataSource = dataSource;
    
    //Update the flags with the current state of the data source
    _gridViewFlags.dataSourceCellForIndex       = [_dataSource respondsToSelector:@selector(gridView:cellForIndex:)];
    _gridViewFlags.dataSourceNumberOfCells      = [_dataSource respondsToSelector:@selector(numberOfCellsInGridView:)];
    _gridViewFlags.dataSourceCanEditCell        = [_dataSource respondsToSelector:@selector(gridView:canEditCellAtIndex:)];
    _gridViewFlags.dataSourceCanMoveCell        = [_dataSource respondsToSelector:@selector(gridView:canMoveCellAtIndex:)];
}

- (void)setHeaderView:(UIView *)headerView
{
    if (self.headerView == headerView)
        return;
    
    //remove the older header view and set up the new header view
    [self.headerView removeFromSuperview];
    _headerView = headerView;
    self.headerView.frame = CGRectMake(0, 0, CGRectGetWidth(self.headerView.frame), CGRectGetHeight(self.headerView.frame));
    self.headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    //Set the origin of the first cell to be beneath this header view
    self.offsetFromHeader = CGRectGetHeight(headerView.bounds);
    
    //add the view to the scroll view
    [self addSubview:self.headerView];
    
    //reset the size of the scroll view to account for this new header views
    self.contentSize = [self contentSizeOfScrollView];
    
    //update any and all visible cells as well
    [self invalidateVisibleCells];
    [self layoutCells];
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if (self.backgroundView == backgroundView)
        return;
    
    //remove the old background view and set up the new one
    [self.backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.backgroundView.frame = self.bounds;
    
    //make sure to insert it BELOW any visible cells
    [self insertSubview:self.backgroundView atIndex:0];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];

    /* If the frame changes, and we're NOT animating, invalidate all of the visible cells and reload the view */
    /* If we ARE animating (eg, orientation change), this will be handled in layoutSubviews. */
    if ([self.layer animationForKey:@"bounds"] == nil)
    {
        [self invalidateVisibleCells];
        [self resetCellMetrics];
    }
    
    //If we were in the middle of dragging a cell, kill it
    if (self.editing)
        [self cancelDraggingCell];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    _editing = editing;
    
    /* If we ended editing, make sure to kill the scroll timer. */
    if (self.editing)
    {
        [self.dragScrollTimer invalidate];
        self.dragScrollTimer = nil;
        
        //deselect and exit edit mode for all visible cells
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            [cell setSelected:NO animated:NO];
            [cell setEditing:NO animated:animated];
        }];
        
        for (TOGridViewCell *cell in self.recycledCells)
        {
            [cell setSelected:NO animated:NO];
            [cell setEditing:NO animated:animated];
        }

        //reset the list of selected cells
        self.selectedCells = nil;
        self.selectedCells = [NSMutableArray array];
    }
    else
    {
        [self enumerateCellDictionary:self.visibleCells withBlock:^(NSInteger index, TOGridViewCell *cell) {
            [cell setEditing:YES animated:animated];
        }];
    }
}

@end
