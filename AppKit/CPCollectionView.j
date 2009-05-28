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

@import <AppKit/CPView.j>


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
    Sets the item prototype to <code>anItem</code>
    @param anItem the new item prototype
*/
- (void)setItemPrototype:(CPCollectionViewItem)anItem
{
    _itemData = [CPKeyedArchiver archivedDataWithRootObject:anItem];
    _itemForDragging = anItem//[CPKeyedUnarchiver unarchiveObjectWithData:_itemData];
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
    Returns a collection view item for <code>anObject</code>.
    @param anObject the object to be represented.
*/
- (CPCollectionViewItem)newItemForRepresentedObject:(id)anObject
{
    var item = nil;
    
    if (_cachedItems.length)
        item = _cachedItems.pop();
    else
        item = [CPKeyedUnarchiver unarchiveObjectWithData:_itemData];

    [item setRepresentedObject:anObject];
    [[item view] setFrameSize:_itemSize];

    return item;
}

// Working with the Responder Chain
/*!
    Returns <code>YES</code> by default.
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
    return [[self window] firstResponder] == self;
}

// Setting the Content
/*!
    Sets the content of the collection view to the content in <code>anArray</code>. 
    This array can be of any type, and each element will be passed to the <code>setRepresentedObject:</code> method.  
    It's the responsibility of your custom collection view item to interpret the object.
    @param anArray the content array
*/
- (void)setContent:(CPArray)anArray
{
    if (_content == anArray)
        return;
    
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
    @param isSelectable <code>YES</code> allows the user to select items.
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
    Returns <code>YES</code> if the collection view is
    selected, and <code>NO</code> otherwise.
*/
- (BOOL)isSelected
{
    return _isSelected;
}

/*!
    Sets whether the user may have no items selected. If YES, mouse clicks not on any item will empty the current selection. The first item will also start off as selected.
    @param shouldAllowMultipleSelection <code>YES</code> allows the user to select multiple items
*/
- (void)setAllowsEmptySelection:(BOOL)shouldAllowEmptySelection
{
    _allowsEmptySelection = shouldAllowEmptySelection;
}

/*!
    Returns <code>YES</code> if the user can select no items, <code>NO</code> otherwise.
*/
- (BOOL)allowsEmptySelection
{
    return _allowsEmptySelection;
}

/*!
    Sets whether the user can select multiple items.
    @param shouldAllowMultipleSelection <code>YES</code> allows the user to select multiple items
*/
- (void)setAllowsMultipleSelection:(BOOL)shouldAllowMultipleSelection
{
    _allowsMultipleSelection = shouldAllowMultipleSelection;
}

/*!
    Returns <code>YES</code> if the user can select multiple items, <code>NO</code> otherwise.
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
    if (_selectionIndexes == anIndexSet || !_isSelectable)
        return;
    
    var index = CPNotFound;
    
    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound)
        [_items[index] setSelected:NO];
    
    _selectionIndexes = anIndexSet;
    
    var index = CPNotFound;
    
    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound)
        [_items[index] setSelected:YES];
    
    if ([_delegate respondsToSelector:@selector(collectionViewDidChangeSelection:)])
        [_delegate collectionViewDidChangeSelection:self]
}

/*!
    Returns a set of the selected indices.
*/
- (CPIndexSet)selectionIndexes
{
    return _selectionIndexes;
}

/* @ignore */
- (void)reloadContent
{   
    // Remove current views
    var count = _items.length;
    
    while (count--)
    {
        [[_items[count] view] removeFromSuperview];
        _cachedItems.push(_items[count]);
    }
    
    _items = [];

    if (!_itemData || !_content)
        return;
    
    var index = 0;
    
    count = _content.length;
        
    for (; index < count; ++index)
    {
        _items.push([self newItemForRepresentedObject:_content[index]]);
    
        [self addSubview:[_items[index] view]];
    }
    
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
    
    _tileLength = length;
    [self setFrameSize:[self _sizeFromLength:length breadth:divisionOffset + itemSizeBreadth + _divisionMargin]];
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

- (void)mouseUp:(CPEvent)anEvent
{
    if ([_selectionIndexes count] && [anEvent clickCount] == 2 && [_delegate respondsToSelector:@selector(collectionView:didDoubleClickOnItemAtIndex:)])
        [_delegate collectionView:self didDoubleClickOnItemAtIndex:[_selectionIndexes firstIndex]];
}

- (void)mouseDown:(CPEvent)anEvent
{
    var location = [self convertPoint:[anEvent locationInWindow] fromView:nil],
        division = FLOOR([self _breadthFromPoint:location] / ([self _breadthFromSize:_itemSize] + _divisionMargin)),
        item = FLOOR([self _lengthFromPoint:location] / ([self _lengthFromSize:_itemSize] + _itemMargin)),
        index = division * _itemsPerDivision + item;
        
    if (index >= 0 && index < _items.length)
        [self setSelectionIndexes:[CPIndexSet indexSetWithIndex:index]];
    else if (_allowsEmptySelection)
        [self setSelectionIndexes:[CPIndexSet indexSet]];
}

- (void)mouseDragged:(CPEvent)anEvent
{
    if (![_delegate respondsToSelector:@selector(collectionView:dragTypesForItemsAtIndexes:)])
        return;
        
    // If we don't have any selected items, we've clicked away, and thus the drag is meaningless.
    if (![_selectionIndexes count])
        return;
        
    // Set up the pasteboard
    var dragTypes = [_delegate collectionView:self dragTypesForItemsAtIndexes:_selectionIndexes];
    
    [[CPPasteboard pasteboardWithName:CPDragPboard] declareTypes:dragTypes owner:self];
    
    var point = [self convertPoint:[anEvent locationInWindow] fromView:nil];

    [_itemForDragging setRepresentedObject:_content[[_selectionIndexes firstIndex]]];

    var view = [_itemForDragging view],
        frame = [view frame];
    
    [view setFrameSize:_itemSize];
    [view setAlphaValue:0.7];
    
    [self dragView:view
        at:[[_items[[_selectionIndexes firstIndex]] view] frame].origin
        offset:CGPointMakeZero()
        event:anEvent
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

@end

/*!
    Represents an object inside a CPCollectionView.
*/
@implementation CPCollectionViewItem : CPObject
{
    id      _representedObject;
    
    CPView  _view;
    
    BOOL    _isSelected;
}

// Setting the Represented Object
/*!
    Sets the object to be represented by this item.
    @param anObject the object to be represented
*/
- (void)setRepresentedObject:(id)anObject
{
    if (_representedObject == anObject)
        return;
    
    _representedObject = anObject;
    
    // FIXME: This should be set up by bindings
    [_view setRepresentedObject:anObject];
}

/*!
    Returns the object represented by this view item
*/
- (id)representedObject
{
    return _representedObject;
}

// Modifying the View
/*!
    Sets the view that is used represent this object.
    @param aView the view used to represent this object
*/
- (void)setView:(CPView)aView
{
    _view = aView;
}

/*!
    Returns the view that represents this object.
*/
- (CPView)view
{
    return _view;
}

// Modifying the Selection
/*!
    Sets whether this view item should be selected.
    @param shouldBeSelected <code>YES</code> makes the item selected. <code>NO</code> deselects it.
*/
- (void)setSelected:(BOOL)shouldBeSelected
{
    if (_isSelected == shouldBeSelected)
        return;
    
    _isSelected = shouldBeSelected;
    
    // FIXME: This should be set up by bindings
    [_view setSelected:_isSelected];
}

/*!
    Returns <code>YES</code> if the item is currently selected. <code>NO</code> if the item is not selected.
*/
- (BOOL)isSelected
{
    return _isSelected;
}

// Parent Collection View
/*!
    Returns the collection view of which this item is a part.
*/
- (CPCollectionView)collectionView
{
    return [_view superview];
}

@end



var CPCollectionViewMinItemSizeKey      = @"CPCollectionViewMinItemSizeKey",
    CPCollectionViewMaxItemSizeKey      = @"CPCollectionViewMaxItemSizeKey",
    CPCollectionViewVerticalMarginKey   = @"CPCollectionViewVerticalMarginKey";
    CPCollectionViewOrientationKey      = @"CPCollectionViewOrientationKey";


@implementation CPCollectionView (CPCoding)

- (id)initWithCoder:(CPCoder)aCoder
{
    self = [super initWithCoder:aCoder];

    if (self)
    {
        _items = [];
        _content = [];

        _cachedItems = [];

        _itemSize = CGSizeMakeZero();
        _minItemSize = [aCoder decodeSizeForKey:CPCollectionViewMinItemSizeKey];
        _maxItemSize = [aCoder decodeSizeForKey:CPCollectionViewMaxItemSizeKey];

        _orientation = [aCoder decodeIntForKey:CPCollectionViewOrientationKey];
        _divisionMargin = [aCoder decodeSizeForKey:CPCollectionViewVerticalMarginKey];
        _tileLength = -1.0;

        _selectionIndexes = [CPIndexSet indexSet];
    }

    return self;
}

- (void)encodeWithCoder:(CPCoder)aCoder
{
    [super encodeWithCoder:aCoder];

    [aCoder encodeSize:_minItemSize forKey:CPCollectionViewMinItemSizeKey];
    [aCoder encodeSize:_maxItemSize forKey:CPCollectionViewMaxItemSizeKey];

    [aCoder encodeInt:_orientation forKey:CPCollectionViewOrientationKey];
    [aCoder encodeSize:_divisionMargin forKey:CPCollectionViewVerticalMarginKey];
}

@end

var CPCollectionViewItemViewKey = @"CPCollectionViewItemViewKey";

@implementation CPCollectionViewItem (CPCoding)

/*
    FIXME Not yet implemented
*/
- (id)copy
{
    
}

@end

var CPCollectionViewItemViewKey = @"CPCollectionViewItemViewKey";

@implementation CPCollectionViewItem (CPCoding)

/*!
    Initializes the view item by unarchiving data from a coder.
    @param aCoder the coder from which the data will be unarchived
    @return the initialized collection view item
*/
- (id)initWithCoder:(CPCoder)aCoder
{
    self = [super init];
    
    if (self)
        _view = [aCoder decodeObjectForKey:CPCollectionViewItemViewKey];
    
    return self;
}

/*!
    Archives the colletion view item to the provided coder.
    @param aCoder the coder to which the view item should be archived
*/
- (void)encodeWithCoder:(CPCoder)aCoder
{
    [aCoder encodeObject:_view forKey:CPCollectionViewItemViewKey];
}

@end
