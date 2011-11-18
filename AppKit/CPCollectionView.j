/*
 * CPCollectionView.j
 * AppKit
 *
 * Created by Francisco Tolmasky.
 * Copyright 2008, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import <Foundation/CPArray.j>
@import <Foundation/CPData.j>
@import <Foundation/CPIndexSet.j>
@import <Foundation/CPKeyedArchiver.j>
@import <Foundation/CPKeyedUnarchiver.j>

@import "CPView.j"
@import "CPCollectionViewItem.j"


/*!
    @ingroup appkit
    @class CPCollectionView

    This class displays an array as a grid of objects, where each object is represented by a view.
    The view is controlled by creating a CPCollectionViewItem and specifying its view, then
    setting that item as the collection view prototype.

    @par Delegate Methods

    @delegate -(void)collectionViewDidChangeSelection:(CPCollectionView)collectionView;
    Called when the selection in the collection view has changed.
    @param collectionView the collection view who's selection changed

    @delegate -(void)collectionView:(CPCollectionView)collectionView didDoubleClickOnItemAtIndex:(int)index;
    Called when the user double-clicks on an item in the collection view.
    @param collectionView the collection view that received the double-click
    @param index the index of the item that received the double-click

    @delegate -(CPData)collectionView:(CPCollectionView)collectionView dataForItemsAtIndexes:(CPIndexSet)indices forType:(CPString)aType;
    Invoked to obtain data for a set of indices.
    @param collectionView the collection view to obtain data for
    @param indices the indices to return data for
    @param aType the data type
    @return a data object containing the index items

    @delegate -(CPArray)collectionView:(CPCollectionView)collectionView dragTypesForItemsAtIndexes:(CPIndexSet)indices;
    Invoked to obtain the data types supported by the specified indices for placement on the pasteboard.
    @param collectionView the collection view the items reside in
    @param indices the indices to obtain drag types
    @return an array of drag types (CPString)
*/

/*
    Items will be arranged in rows stacked vertically. The collection views height will be adjusted to fit the items.
    @group CPCollectionViewOrientation
    @global
*/
CPCollectionViewVerticalOrientation = 0;
/*
    Items will be arranged in columns stacked horizontally. The collection views width will be adjusted to fit the items.
    @group CPCollectionViewOrientation
    @global
*/
CPCollectionViewHorizontalOrientation = 1;


@implementation CPCollectionView : CPView
{
    /*
     This version of CPCollectionView supports horizontal and vertical orientations. The following members
     have been renamed to reflect this:
     
    _tileWidth => _tileLength
    _horizontalMargin => _itemMargin
    _verticalMargin => _divisionMargin
    _numberOfRows => _numberOfDivisions
    _numberOfColumns => _itemsPerDivision
    */

    CPArray                 _content;
    CPArray                 _items;

    CPData                  _itemData;
    CPCollectionViewItem    _itemPrototype;
    CPCollectionViewItem    _itemForDragging;
    CPMutableArray          _cachedItems;

    unsigned                _maxNumberOfRows;
    unsigned                _maxNumberOfColumns;

    CGSize                  _minItemSize;
    CGSize                  _maxItemSize;

    CPArray                 _backgroundColors;

    float                   _tileLength;
    
    BOOL                    _isSelectable;
    BOOL                    _allowsMultipleSelection;
    BOOL                    _allowsEmptySelection;
    CPIndexSet              _selectionIndexes;

    CGSize                  _itemSize;
    
    float                   _itemMargin;
    float                   _divisionMargin;
    
    unsigned                _numberOfDivisions;
    unsigned                _itemsPerDivision;

    int                     _orientation;
    
    id                      _delegate;

    CPEvent                 _mouseDownEvent;
}

- (id)initWithFrame:(CGRect)aFrame
{
    self = [super initWithFrame:aFrame];

    if (self)
    {
        _items = [];
        _content = [];

        _cachedItems = [];

        _itemSize = CGSizeMakeZero();
        _minItemSize = CGSizeMakeZero();
        _maxItemSize = CGSizeMakeZero();

        [self setBackgroundColors:nil];
        
        _orientation = CPCollectionViewVerticalOrientation;
        _divisionMargin = 5.0;
        _tileLength = -1.0;
        
        _selectionIndexes = [CPIndexSet indexSet];
        _allowsEmptySelection = YES;
        _isSelectable = YES;
    }

    return self;
}

/*!
    Sets the item prototype to \c anItem

    The item prototype should implement the CPCoding protocol
    because the item is copied by archiving and unarchiving the
    prototypal view.

    Example:

    <pre>
      @implement MyCustomView : CPCollectionViewItem
      {
          CPArray   items   @accessors;
      }

      - (id)initWithFrame:(CGRect)aFrame
      {
        self = [super initWithFrame:aFrame];
        if (self)
        {
          items = [];
        }
        return self;
      }

      - (id)initWithCoder:(CPCoder)aCoder
      {
        self = [super initWithCoder:aCoder];
        items = [aCoder decodeObjectForKey:@"KEY"];
        return self;
      }

      - (void)encodeWithCoder:(CPCoder)aCoder
      {
        [aCoder encodeObject:items forKey:@"KEY"];
        [super encodeWithCoder:aCoder];
      }

      @end
    </pre>

    This will allow the collection view to create multiple 'clean' copies
    of the item prototype which will maintain the original values for item
    and all of the properties archived by the super class.

    @param anItem the new item prototype
*/
- (void)setItemPrototype:(CPCollectionViewItem)anItem
{
    _cachedItems = [];
    _itemData = nil;
    _itemForDragging = nil;
    _itemPrototype = anItem;

    [self reloadContent];
}

/*!
    Returns the current item prototype
*/
- (CPCollectionViewItem)itemPrototype
{
    return _itemPrototype;
}

/*!
    Returns a collection view item for \c anObject.
    @param anObject the object to be represented.
*/
- (CPCollectionViewItem)newItemForRepresentedObject:(id)anObject
{
    var item = nil;

    if (_cachedItems.length)
        item = _cachedItems.pop();

    else
    {
        if (!_itemData)
            if (_itemPrototype)
                _itemData = [CPKeyedArchiver archivedDataWithRootObject:_itemPrototype];

        item = [CPKeyedUnarchiver unarchiveObjectWithData:_itemData];
    }

    [item setRepresentedObject:anObject];
    [[item view] setFrameSize:_itemSize];

    return item;
}

// Working with the Responder Chain
/*!
    Returns \c YES by default.
*/
- (BOOL)acceptsFirstResponder
{
    return YES;
}

/*!
    Returns whether the receiver is currently the first responder.
*/
- (BOOL)isFirstResponder
{
    return [[self window] firstResponder] === self;
}

// Setting the Content
/*!
    Sets the content of the collection view to the content in \c anArray.
    This array can be of any type, and each element will be passed to the \c -setRepresentedObject: method.
    It's the responsibility of your custom collection view item to interpret the object.
    @param anArray the content array
*/
- (void)setContent:(CPArray)anArray
{
    // reset the _selectionIndexes
    [self setSelectionIndexes:[CPIndexSet indexSet]];

    _content = anArray;

    [self reloadContent];
}

/*!
    Returns the collection view content array
*/
- (CPArray)content
{
    return _content;
}

/*!
    Returns the collection view items.
*/
- (CPArray)items
{
    return _items;
}

// Setting the Selection Mode
/*!
    Sets whether the user is allowed to select items
    @param isSelectable \c YES allows the user to select items.
*/
- (void)setSelectable:(BOOL)isSelectable
{
    if (_isSelectable == isSelectable)
        return;

    _isSelectable = isSelectable;

    if (!_isSelectable)
    {
        var index = CPNotFound;

        while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound)
            [_items[index] setSelected:NO];
    }
}

/*!
    Returns \c YES if the collection view is
    selectable, and \c NO otherwise.
*/
- (BOOL)isSelectable
{
    return _isSelectable;
}

/*!
    Sets whether the user may have no items selected. If YES, mouse clicks not on any item will empty the current selection. The first item will also start off as selected.
    @param shouldAllowMultipleSelection \c YES allows the user to select multiple items
*/
- (void)setAllowsEmptySelection:(BOOL)shouldAllowEmptySelection
{
    _allowsEmptySelection = shouldAllowEmptySelection;
}

/*!
    Returns \c YES if the user can select no items, \c NO otherwise.
*/
- (BOOL)allowsEmptySelection
{
    return _allowsEmptySelection;
}

/*!
    Sets whether the user can select multiple items.
    @param shouldAllowMultipleSelection \c YES allows the user to select multiple items
*/
- (void)setAllowsMultipleSelection:(BOOL)shouldAllowMultipleSelection
{
    _allowsMultipleSelection = shouldAllowMultipleSelection;
}

/*!
    Returns \c YES if the user can select multiple items, \c NO otherwise.
*/
- (BOOL)allowsMultipleSelection
{
    return _allowsMultipleSelection;
}

/*!
    Sets the selected items based on the provided indices.
    @param anIndexSet the set of items to be selected
*/
- (void)setSelectionIndexes:(CPIndexSet)anIndexSet
{
    if ([_selectionIndexes isEqual:anIndexSet] || !_isSelectable)
        return;

    var index = CPNotFound;

    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound)
        [_items[index] setSelected:NO];

    _selectionIndexes = anIndexSet;

    var index = CPNotFound;

    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound)
        [_items[index] setSelected:YES];

    var binderClass = [[self class] _binderClassForBinding:@"selectionIndexes"];
    [[binderClass getBinding:@"selectionIndexes" forObject:self] reverseSetValueFor:@"selectionIndexes"];

    if ([_delegate respondsToSelector:@selector(collectionViewDidChangeSelection:)])
        [_delegate collectionViewDidChangeSelection:self];
}

/*!
    Returns a set of the selected indices.
*/
- (CPIndexSet)selectionIndexes
{
    return [_selectionIndexes copy];
}

/* @ignore */
- (void)reloadContent
{
    // Remove current views
    var count = _items.length;

    while (count--)
    {
        [[_items[count] view] removeFromSuperview];
        [_items[count] setSelected:NO];

        _cachedItems.push(_items[count]);
    }

    _items = [];

    if (!_itemPrototype)
        return;

    var index = 0;

    count = _content.length;

    for (; index < count; ++index)
    {
        _items.push([self newItemForRepresentedObject:_content[index]]);

        [self addSubview:[_items[index] view]];
    }

    index = CPNotFound;
    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound)
        [_items[index] setSelected:YES];

    [self tile];
}

// Private convenience functions to access dimensions taking account of collection view orientation 

/* @ignore */
- (float)_lengthFromSize:(CGSize)aSize
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? aSize.width : aSize.height;
}

/* @ignore */
- (float)_breadthFromSize:(CGSize)aSize
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? aSize.height : aSize.width;
}

/* @ignore */
- (CGSize)_sizeFromLength:(float)aLength breadth:(float)aBreadth
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? CGSizeMake(aLength, aBreadth) : CGSizeMake(aBreadth, aLength);
}

/* @ignore */
- (float)_lengthFromPoint:(CGPoint)aPoint
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? aPoint.x : aPoint.y;
}

/* @ignore */
- (float)_breadthFromPoint:(CGPoint)aPoint
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? aPoint.y : aPoint.x;
}

/* @ignore */
- (CGPoint)_pointFromLength:(float)aLength breadth:(float)aBreadth
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? CGPointMake(aLength, aBreadth) : CGPointMake(aBreadth, aLength);
}


/* @ignore */
- (void)tile
{
    var length = [self _lengthFromSize:[self bounds].size];
        
    if (![_content count] || length == _tileLength)
        return;
        
    // We try to fit as many views per division as possible.  Any remaining space is then 
    // either proportioned out to the views (if their minSize != maxSize) or used as
    // margin
    var itemSizeLength = [self _lengthFromSize:_minItemSize],
        itemSizeBreadth = [self _breadthFromSize:_minItemSize];
    
    _itemsPerDivision = MAX(1.0, FLOOR(length / itemSizeLength));
    
    var maxItemsPerDivision = (_orientation === CPCollectionViewVerticalOrientation) ?  _maxNumberOfColumns : _maxNumberOfRows;

    if (maxItemsPerDivision > 0)
        _itemsPerDivision = MIN(maxItemsPerDivision, _itemsPerDivision);
            
    var remaining = length - _itemsPerDivision * itemSizeLength,
        itemsNeedSizeUpdate = NO,
        maxItemSizeLength = [self _lengthFromSize:_maxItemSize];
        
    if (remaining > 0 && itemSizeLength < maxItemSizeLength)
        itemSizeLength = MIN(maxItemSizeLength, itemSizeLength + FLOOR(remaining / _itemsPerDivision));
    
    // When we have ONE division and a non-integral length, the FLOORing above can cause the item length to be smaller than the total length.
    if (maxItemsPerDivision == 1 && itemSizeLength < maxItemSizeLength && itemSizeLength < length)
        itemSizeLength = MIN(maxItemSizeLength, length);
    
    var itemSize = [self _sizeFromLength:itemSizeLength breadth:itemSizeBreadth];

    if (!CGSizeEqualToSize(_itemSize, itemSize))
    {
        _itemSize = itemSize;
        itemsNeedSizeUpdate = YES;
    }

    var index = 0,
        count = _items.length;

    if (_maxNumberOfColumns > 0 && _maxNumberOfRows > 0)
        count = MIN(count, _maxNumberOfColumns * _maxNumberOfRows);
    
    _numberOfDivisions = CEIL(count / _itemsPerDivision);

    _itemMargin = FLOOR((length - _itemsPerDivision * itemSizeLength) / (_itemsPerDivision + 1));
        
    var itemOffset = _itemMargin,
        divisionOffset = -itemSizeBreadth;
    
    for (; index < count; ++index)
    {
        if (index % _itemsPerDivision == 0)
        {
            itemOffset = _itemMargin;
            divisionOffset += _divisionMargin + itemSizeBreadth;
        }

        var view = [_items[index] view];
        
        [view setFrameOrigin:[self _pointFromLength:itemOffset breadth:divisionOffset]];
        
        if (itemsNeedSizeUpdate)
            [view setFrameSize:_itemSize];
            
        itemOffset += itemSizeLength + _itemMargin;
    }

    var superview = [self superview],
        proposedSize = [self _sizeFromLength:length breadth:divisionOffset + itemSizeBreadth + _divisionMargin];

    if ([superview isKindOfClass:[CPClipView class]])
    {
        var superviewSize = [superview bounds].size;
        proposedSize.height = MAX(superviewSize.height, proposedSize.height);
    }

    _tileLength = length;
    [self setFrameSize:proposedSize];
    _tileLength = -1.0;
}

- (void)resizeSubviewsWithOldSize:(CGSize)aSize
{
    [self tile];
}

// Laying Out the Collection View
/*!
    Sets the maximum number of rows.
    @param aMaxNumberOfRows the new maximum number of rows
*/
- (void)setMaxNumberOfRows:(unsigned)aMaxNumberOfRows
{
    if (_maxNumberOfRows == aMaxNumberOfRows)
        return;

    _maxNumberOfRows = aMaxNumberOfRows;

    [self tile];
}

/*!
    Returns the maximum number of rows.
*/
- (unsigned)maxNumberOfRows
{
    return _maxNumberOfRows;
}

/*!
    Sets the maximum number of columns.
    @param aMaxNumberOfColumns the new maximum number of columns
*/
- (void)setMaxNumberOfColumns:(unsigned)aMaxNumberOfColumns
{
    if (_maxNumberOfColumns == aMaxNumberOfColumns)
        return;

    _maxNumberOfColumns = aMaxNumberOfColumns;

    [self tile];
}

/*!
    Returns the maximum number of columns
*/
- (unsigned)maxNumberOfColumns
{
    return _maxNumberOfColumns;
}

/*!
    Returns the current number of rows
*/
- (unsigned)numberOfRows
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? _numberOfDivisions : _itemsPerDivision;
}

/*!
    Returns the current number of columns
*/

- (unsigned)numberOfColumns
{
    return (_orientation === CPCollectionViewVerticalOrientation) ? _itemsPerDivision : _numberOfDivisions;
}

/*!
    Sets the minimum size for an item
    @param aSize the new minimum item size
*/
- (void)setMinItemSize:(CGSize)aSize
{
    if (CGSizeEqualToSize(_minItemSize, aSize))
        return;

    _minItemSize = CGSizeMakeCopy(aSize);

    [self tile];
}

/*!
    Returns the current minimum item size
*/
- (CGSize)minItemSize
{
    return _minItemSize;
}

/*!
    Sets the maximum item size.
    @param aSize the new maximum item size
*/
- (void)setMaxItemSize:(CGSize)aSize
{
    if (CGSizeEqualToSize(_maxItemSize, aSize))
        return;

    _maxItemSize = CGSizeMakeCopy(aSize);

    [self tile];
}

/*!
    Returns the current maximum item size.
*/
- (CGSize)maxItemSize
{
    return _maxItemSize;
}

- (void)setBackgroundColors:(CPArray)backgroundColors
{
    if (_backgroundColors === backgroundColors)
        return;

    _backgroundColors = backgroundColors;

    if (!_backgroundColors)
        _backgroundColors = [CPColor whiteColor];

    if ([_backgroundColors count] === 1)
        [self setBackgroundColor:_backgroundColors[0]];

    else
        [self setBackgroundColor:nil];

    [self setNeedsDisplay:YES];
}

- (CPArray)backgroundColors
{
    return _backgroundColors;
}

- (void)mouseUp:(CPEvent)anEvent
{
    if ([_selectionIndexes count] && [anEvent clickCount] == 2 && [_delegate respondsToSelector:@selector(collectionView:didDoubleClickOnItemAtIndex:)])
        [_delegate collectionView:self didDoubleClickOnItemAtIndex:[_selectionIndexes firstIndex]];
}

- (void)mouseDown:(CPEvent)anEvent
{
    _mouseDownEvent = anEvent;

    var location = [self convertPoint:[anEvent locationInWindow] fromView:nil],
        index = [self _indexAtPoint:location];

    if (index >= 0 && index < _items.length)
    {
        if (_allowsMultipleSelection && ([anEvent modifierFlags] & CPCommandKeyMask || [anEvent modifierFlags] & CPShiftKeyMask))
        {
            if ([anEvent modifierFlags] & CPCommandKeyMask)
            {
                var indexes = [_selectionIndexes copy];

                if ([indexes containsIndex:index])
                    [indexes removeIndex:index];
                else
                    [indexes addIndex:index];
            }
            else if ([anEvent modifierFlags] & CPShiftKeyMask)
            {
                var firstSelectedIndex = [[self selectionIndexes] firstIndex],
                    newSelectedRange = nil;

                if (index < firstSelectedIndex)
                    newSelectedRange = CPMakeRange(index, (firstSelectedIndex - index) + 1);
                else
                    newSelectedRange = CPMakeRange(firstSelectedIndex, (index - firstSelectedIndex) + 1);

                indexes = [[self selectionIndexes] copy];
                [indexes addIndexesInRange:newSelectedRange];
            }
        }
        else
            indexes = [CPIndexSet indexSetWithIndex:index];

        [self setSelectionIndexes:indexes];
    }
    else if (_allowsEmptySelection)
        [self setSelectionIndexes:[CPIndexSet indexSet]];
}

- (void)mouseDragged:(CPEvent)anEvent
{
    var locationInWindow = [anEvent locationInWindow],
        mouseDownLocationInWindow = [_mouseDownEvent locationInWindow];

    // FIXME: This is because Safari's drag hysteresis is 3px x 3px
    if ((ABS(locationInWindow.x - mouseDownLocationInWindow.x) < 3) &&
        (ABS(locationInWindow.y - mouseDownLocationInWindow.y) < 3))
        return;

    if (![_delegate respondsToSelector:@selector(collectionView:dragTypesForItemsAtIndexes:)])
        return;

    // If we don't have any selected items, we've clicked away, and thus the drag is meaningless.
    if (![_selectionIndexes count])
        return;

    if ([_delegate respondsToSelector:@selector(collectionView:canDragItemsAtIndexes:withEvent:)] &&
        ![_delegate collectionView:self canDragItemsAtIndexes:_selectionIndexes withEvent:_mouseDownEvent])
        return;

    // Set up the pasteboard
    var dragTypes = [_delegate collectionView:self dragTypesForItemsAtIndexes:_selectionIndexes];

    [[CPPasteboard pasteboardWithName:CPDragPboard] declareTypes:dragTypes owner:self];

    if (!_itemForDragging)
        _itemForDragging = [self newItemForRepresentedObject:_content[[_selectionIndexes firstIndex]]];
    else
        [_itemForDragging setRepresentedObject:_content[[_selectionIndexes firstIndex]]];

    var view = [_itemForDragging view];

    [view setFrameSize:_itemSize];
    [view setAlphaValue:0.7];

    [self dragView:view
        at:[[_items[[_selectionIndexes firstIndex]] view] frame].origin
        offset:CGSizeMakeZero()
        event:_mouseDownEvent
        pasteboard:nil
        source:self
        slideBack:YES];
}

/*!
    Places the selected items on the specified pasteboard. The items are requested from the collection's delegate.
    @param aPasteboard the pasteboard to put the items on
    @param aType the format the pasteboard data
*/
- (void)pasteboard:(CPPasteboard)aPasteboard provideDataForType:(CPString)aType
{
    [aPasteboard setData:[_delegate collectionView:self dataForItemsAtIndexes:_selectionIndexes forType:aType] forType:aType];
}

// Cappuccino Additions

/*!
    Sets the orientation for the collection view. With the default <code>CPCollectionViewVerticalOrientation</code>
    the view has fixed width, items are arranged in rows starting at the top and the height is varied to fit the items.
    With <code>CPCollectionViewHorizontalOrientation</code> the view has fixed height, items are arranged in 
    columns starting on the left and the width is varied. 
    @param anOrientation the orientation to use
*/

- (void)setOrientation:(CPCollectionViewOrientation)anOrientation
{
    if (_orientation === anOrientation)
        return;

    _orientation = anOrientation;

    [self tile];
}

/*!
    Gets the orientation for the collection view.
*/

- (CPCollectionViewOrientation)orientation
{
    return _orientation;
}

/*!
    Sets the collection view's spacing between element divisions.
    @param aDivisionMargin the number of pixels to place between element divisions
*/

- (void)setDivisionMargin:(float)aDivisionMargin
{
    if (_divisionMargin == aDivisionMargin)
        return;
    
    _divisionMargin = aDivisionMargin;
    
    [self tile];
}

/*!
    Gets the collection view's current spacing between element divisions.
*/

- (float)divisionMargin
{
    return _divisionMargin;
}

/*!
    @deprecated use setDivisionMargin: instead

    Sets the collection view's spacing between element divisions.
    @param aVerticalMargin the number of pixels to place between elements
*/

- (void)setVerticalMargin:(float)aVerticalMargin
{
    [self setDivisionMargin:aVerticalMargin];
}

/*!
    @deprecated use divisionMargin instead

    Gets the collection view's current spacing between element divisions.
*/

- (float)verticalMargin
{
    return [self divisionMargin];
}

/*!
    Sets the collection view's delegate
    @param aDelegate the new delegate
*/
- (void)setDelegate:(id)aDelegate
{
    _delegate = aDelegate;
}

/*!
    Returns the collection view's delegate
*/
- (id)delegate
{
    return _delegate;
}

/*!
    @ignore
*/
- (CPMenu)menuForEvent:(CPEvent)theEvent
{
    if (![[self delegate] respondsToSelector:@selector(collectionView:menuForItemAtIndex:)])
        return [super menuForEvent:theEvent];

    var location = [self convertPoint:[theEvent locationInWindow] fromView:nil],
        index = [self _indexAtPoint:location];

    return [_delegate collectionView:self menuForItemAtIndex:index];
}

- (int)_indexAtPoint:(CGPoint)thePoint
{
    var division = FLOOR([self _breadthFromPoint:thePoint] / ([self _breadthFromSize:_itemSize] + _divisionMargin)),
        item = FLOOR([self _lengthFromPoint:thePoint] / ([self _lengthFromSize:_itemSize] + _itemMargin));

    return division * _itemsPerDivision + item;
}

- (CPCollectionViewItem)itemAtIndex:(unsigned)anIndex
{
    return [_items objectAtIndex:anIndex];
}

- (CGRect)frameForItemAtIndex:(unsigned)anIndex
{
    return [[[self itemAtIndex:anIndex] view] frame];
}

- (CGRect)frameForItemsAtIndexes:(CPIndexSet)anIndexSet
{
    var indexArray = [],
        frame = CGRectNull;

    [anIndexSet getIndexes:indexArray maxCount:-1 inIndexRange:nil];

    var index = 0,
        count = [indexArray count];

    for (; index < count; ++index)
        frame = CGRectUnion(frame, [self frameForItemAtIndex:indexArray[index]]);

    return frame;
}

@end

@implementation CPCollectionView (KeyboardInteraction)

- (void)_modifySelectionWithNewIndex:(int)anIndex direction:(int)aDirection expand:(BOOL)shouldExpand
{
    anIndex = MIN(MAX(anIndex, 0), [[self items] count] - 1);

    if (_allowsMultipleSelection && shouldExpand)
    {
        var indexes = [_selectionIndexes copy],
            bottomAnchor = [indexes firstIndex],
            topAnchor = [indexes lastIndex];

        // if the direction is backward (-1) check with the bottom anchor
        if (aDirection === -1)
            [indexes addIndexesInRange:CPMakeRange(anIndex, bottomAnchor - anIndex + 1)];
        else
            [indexes addIndexesInRange:CPMakeRange(topAnchor, anIndex -  topAnchor + 1)];
    }
    else
        indexes = [CPIndexSet indexSetWithIndex:anIndex];

    [self setSelectionIndexes:indexes];
    [self _scrollToSelection];
}

- (void)_scrollToSelection
{
    var frame = [self frameForItemsAtIndexes:[self selectionIndexes]];

    if (!CGRectIsNull(frame))
        [self scrollRectToVisible:frame];
}

- (void)moveLeft:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index === CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - 1 direction:-1 expand:NO];
}

- (void)moveLeftAndModifySelection:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index === CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - 1 direction:-1 expand:YES];
}

- (void)moveRight:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + 1 direction:1 expand:NO];
}

- (void)moveRightAndModifySelection:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + 1 direction:1 expand:YES];
}

- (void)moveDown:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + [self numberOfColumns] direction:1 expand:NO];
}

- (void)moveDownAndModifySelection:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + [self numberOfColumns] direction:1 expand:YES];
}

- (void)moveUp:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index == CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - [self numberOfColumns] direction:-1 expand:NO];
}

- (void)moveUpAndModifySelection:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index == CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - [self numberOfColumns] direction:-1 expand:YES];
}

- (void)deleteBackward:(id)sender
{
    if ([[self delegate] respondsToSelector:@selector(collectionView:shouldDeleteItemsAtIndexes:)])
    {
        [[self delegate] collectionView:self shouldDeleteItemsAtIndexes:[self selectionIndexes]];

        var index = [[self selectionIndexes] firstIndex];
        if (index > [[self content] count] - 1)
            [self setSelectionIndexes:[CPIndexSet indexSetWithIndex:[[self content] count] - 1]];

        [self _scrollToSelection];
        [self setNeedsDisplay:YES];
    }
}

- (void)keyDown:(CPEvent)anEvent
{
    [self interpretKeyEvents:[anEvent]];
}

@end

@implementation CPCollectionView (Deprecated)

- (CGRect)rectForItemAtIndex:(int)anIndex
{
    _CPReportLenientDeprecation([self class], _cmd, @selector(frameForItemAtIndex:));

    // Don't re-compute anything just grab the current frame
    // This allows subclasses to override tile without messing this up.
    return [self frameForItemAtIndex:anIndex];
}

- (CGRect)rectForItemsAtIndexes:(CPIndexSet)anIndexSet
{
    _CPReportLenientDeprecation([self class], _cmd, @selector(frameForItemsAtIndexes:));

    return [self frameForItemsAtIndexes:anIndexSet];
}

@end

var CPCollectionViewMinItemSizeKey              = @"CPCollectionViewMinItemSizeKey",
    CPCollectionViewMaxItemSizeKey              = @"CPCollectionViewMaxItemSizeKey",
    CPCollectionViewVerticalMarginKey           = @"CPCollectionViewVerticalMarginKey",
    CPCollectionViewMaxNumberOfRowsKey          = @"CPCollectionViewMaxNumberOfRowsKey",
    CPCollectionViewMaxNumberOfColumnsKey       = @"CPCollectionViewMaxNumberOfColumnsKey",
    CPCollectionViewSelectableKey               = @"CPCollectionViewSelectableKey",
    CPCollectionViewAllowsMultipleSelectionKey  = @"CPCollectionViewAllowsMultipleSelectionKey",
    CPCollectionViewBackgroundColorsKey         = @"CPCollectionViewBackgroundColorsKey";
    CPCollectionViewOrientationKey              = @"CPCollectionViewOrientationKey";


@implementation CPCollectionView (CPCoding)

- (void)awakeFromCib
{
    [super awakeFromCib];

    if (CGSizeEqualToSize(_minItemSize, CGSizeMakeZero()) || CGSizeEqualToSize(_maxItemSize, CGSizeMakeZero()))
    {
        var item = _itemPrototype;

        if (CGSizeEqualToSize(_minItemSize, CGSizeMakeZero()))
            _minItemSize = [[item view] frameSize];
        else if (CGSizeEqualToSize(_maxItemSize, CGSizeMakeZero()))
            _maxItemSize = [[item view] frameSize];
    }
}

- (id)initWithCoder:(CPCoder)aCoder
{
    self = [super initWithCoder:aCoder];

    if (self)
    {
        _items = [];
        _content = [];

        _cachedItems = [];

        _itemSize = CGSizeMakeZero();

        _minItemSize = [aCoder decodeSizeForKey:CPCollectionViewMinItemSizeKey] || CGSizeMakeZero();
        _maxItemSize = [aCoder decodeSizeForKey:CPCollectionViewMaxItemSizeKey] || CGSizeMakeZero();

        _maxNumberOfRows = [aCoder decodeIntForKey:CPCollectionViewMaxNumberOfRowsKey] || 0;
        _maxNumberOfColumns = [aCoder decodeIntForKey:CPCollectionViewMaxNumberOfColumnsKey] || 0;

        _divisionMargin = [aCoder decodeFloatForKey:CPCollectionViewVerticalMarginKey];

        _isSelectable = [aCoder decodeBoolForKey:CPCollectionViewSelectableKey];
        _allowsMultipleSelection = [aCoder decodeBoolForKey:CPCollectionViewAllowsMultipleSelectionKey];

        _orientation = [aCoder decodeIntForKey:CPCollectionViewOrientationKey];

        [self setBackgroundColors:[aCoder decodeObjectForKey:CPCollectionViewBackgroundColorsKey]];
          
        _tileLength = -1.0;

        _selectionIndexes = [CPIndexSet indexSet];

        _allowsEmptySelection = YES;
    }

    return self;
}

- (void)encodeWithCoder:(CPCoder)aCoder
{
    [super encodeWithCoder:aCoder];

    if (!CGSizeEqualToSize(_minItemSize, CGSizeMakeZero()))
      [aCoder encodeSize:_minItemSize forKey:CPCollectionViewMinItemSizeKey];

    if (!CGSizeEqualToSize(_maxItemSize, CGSizeMakeZero()))
      [aCoder encodeSize:_maxItemSize forKey:CPCollectionViewMaxItemSizeKey];

    [aCoder encodeInt:_maxNumberOfRows forKey:CPCollectionViewMaxNumberOfRowsKey];
    [aCoder encodeInt:_maxNumberOfColumns forKey:CPCollectionViewMaxNumberOfColumnsKey];

    [aCoder encodeBool:_isSelectable forKey:CPCollectionViewSelectableKey];
    [aCoder encodeBool:_allowsMultipleSelection forKey:CPCollectionViewAllowsMultipleSelectionKey];

    [aCoder encodeFloat:_divisionMargin forKey:CPCollectionViewVerticalMarginKey];

    [aCoder encodeObject:_backgroundColors forKey:CPCollectionViewBackgroundColorsKey];

    [aCoder encodeInt:_orientation forKey:CPCollectionViewOrientationKey];
}

@end
