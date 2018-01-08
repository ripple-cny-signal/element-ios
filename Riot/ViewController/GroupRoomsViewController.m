/*
 Copyright 2017 Vector Creations Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "GroupRoomsViewController.h"

#import "AppDelegate.h"

#import "GroupRoomTableViewCell.h"

#import "RageShakeManager.h"

@interface GroupRoomsViewController ()
{
    // Search result
    NSString *currentSearchText;
    NSMutableArray<MXGroupRoom*> *filteredGroupRooms;
    
    // Observe kRiotDesignValuesDidChangeThemeNotification to handle user interface theme change.
    id kRiotDesignValuesDidChangeThemeNotificationObserver;
}

@end

@implementation GroupRoomsViewController

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass(self.class)
                          bundle:[NSBundle bundleForClass:self.class]];
}

+ (instancetype)groupRoomsViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass(self.class)
                                          bundle:[NSBundle bundleForClass:self.class]];
}

#pragma mark -

- (void)finalizeInit
{
    [super finalizeInit];
    
    // Setup `MXKViewControllerHandling` properties
    self.enableBarTintColorStatusChange = NO;
    self.rageShakeManager = [RageShakeManager sharedManager];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // Check whether the view controller has been pushed via storyboard
    if (!self.tableView)
    {
        // Instantiate view controller objects
        [[[self class] nib] instantiateWithOwner:self options:nil];
    }
    
    // Adjust Top and Bottom constraints to take into account potential navBar and tabBar.
    [NSLayoutConstraint deactivateConstraints:@[_searchBarTopConstraint, _tableViewBottomConstraint]];
    
    _searchBarTopConstraint = [NSLayoutConstraint constraintWithItem:self.topLayoutGuide
                                                           attribute:NSLayoutAttributeBottom
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:self.searchBarHeader
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0f
                                                            constant:0.0f];
    
    _tableViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.bottomLayoutGuide
                                                              attribute:NSLayoutAttributeTop
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:self.tableView
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0f
                                                               constant:0.0f];
    
    [NSLayoutConstraint activateConstraints:@[_searchBarTopConstraint, _tableViewBottomConstraint]];
    
    _searchBarView.placeholder = NSLocalizedStringFromTable(@"group_rooms_filter_rooms", @"Vector", nil);
    _searchBarView.returnKeyType = UIReturnKeyDone;
    _searchBarView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    
    // Search bar header is hidden when no group is provided
    _searchBarHeader.hidden = (self.group == nil);
    
    // Enable self-sizing cells and section headers.
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74;
    self.tableView.sectionHeaderHeight = 0;
    
    // Hide line separators of empty cells
    self.tableView.tableFooterView = [[UIView alloc] init];
    
    [self.tableView registerClass:GroupRoomTableViewCell.class forCellReuseIdentifier:@"RoomTableViewCellId"];
    
    // Observe user interface theme change.
    kRiotDesignValuesDidChangeThemeNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kRiotDesignValuesDidChangeThemeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        [self userInterfaceThemeDidChange];
        
    }];
    [self userInterfaceThemeDidChange];
}

- (void)userInterfaceThemeDidChange
{
    self.defaultBarTintColor = kRiotSecondaryBgColor;
    self.barTitleColor = kRiotPrimaryTextColor;
    self.activityIndicator.backgroundColor = kRiotOverlayColor;
    
    [self refreshSearchBarItemsColor:_searchBarView];
    
    _searchBarHeaderBorder.backgroundColor = kRiotAuxiliaryColor;
    
    // Check the table view style to select its bg color.
    self.tableView.backgroundColor = ((self.tableView.style == UITableViewStylePlain) ? kRiotPrimaryBgColor : kRiotSecondaryBgColor);
    self.view.backgroundColor = self.tableView.backgroundColor;
    
    if (self.tableView.dataSource)
    {
        [self.tableView reloadData];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return kRiotDesignStatusBarStyle;
}

// This method is called when the viewcontroller is added or removed from a container view controller.
- (void)didMoveToParentViewController:(nullable UIViewController *)parent
{
    [super didMoveToParentViewController:parent];
}

- (void)destroy
{
    if (kRiotDesignValuesDidChangeThemeNotificationObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:kRiotDesignValuesDidChangeThemeNotificationObserver];
        kRiotDesignValuesDidChangeThemeNotificationObserver = nil;
    }
    
    _group = nil;
    _mxSession = nil;
    
    filteredGroupRooms = nil;
    
    groupRooms = nil;
    
    // Note: all observers are removed during super call.
    [super destroy];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // Screen tracking
    [[AppDelegate theDelegate] trackScreen:@"GroupDetailsRooms"];
    
    if (_group)
    {
        // Restore the listeners on the group update.
        [self registerOnGroupChangeNotifications];
        
        // Check whether the selected group is stored in the user's session, or if it is a group preview.
        // Replace the displayed group instance with the one stored in the session (if any).
        MXGroup *storedGroup = [_mxSession groupWithGroupId:_group.groupId];
        BOOL isPreview = (!storedGroup);
        
        // Force refresh
        [self refreshDisplayWithGroup:(isPreview ? _group : storedGroup)];
        
        // Prepare a block called on successful update in case of a group preview.
        // Indeed the group update notifications are triggered by the matrix session only for the user's groups.
        void (^success)(void) = ^void(void)
        {
            [self refreshDisplayWithGroup:_group];
        };
        
        // Trigger a refresh on the group rooms.
        [self.mxSession updateGroupRooms:_group success:(isPreview ? success : nil) failure:^(NSError *error) {
            
            NSLog(@"[GroupRoomsViewController] viewWillAppear: group rooms update failed %@", _group.groupId);
            
        }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self cancelRegistrationOnGroupChangeNotifications];
    
    // cancel any pending search
    [self searchBarCancelButtonClicked:_searchBarView];
}

- (void)withdrawViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    // Check whether the current view controller is displayed inside a segmented view controller in order to withdraw the right item
    if (self.parentViewController && [self.parentViewController isKindOfClass:SegmentedViewController.class])
    {
        [((SegmentedViewController*)self.parentViewController) withdrawViewControllerAnimated:animated completion:completion];
    }
    else
    {
        [super withdrawViewControllerAnimated:animated completion:completion];
    }
}

- (void)setGroup:(MXGroup*)group withMatrixSession:(MXSession*)mxSession
{
    // Cancel any pending search
    [self searchBarCancelButtonClicked:_searchBarView];
    
    if (_mxSession != mxSession)
    {
        [self cancelRegistrationOnGroupChangeNotifications];
        _mxSession = mxSession;
        
        [self registerOnGroupChangeNotifications];
    }
    
    [self addMatrixSession:mxSession];
    
    [self refreshDisplayWithGroup:group];
}

#pragma mark -

- (void)registerOnGroupChangeNotifications
{
    if (_mxSession)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateGroupRooms:) name:kMXSessionDidUpdateGroupRoomsNotification object:_mxSession];
    }
}

- (void)cancelRegistrationOnGroupChangeNotifications
{
    // Remove any pending observers
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXSessionDidUpdateGroupRoomsNotification object:_mxSession];
}

- (void)didUpdateGroupRooms:(NSNotification *)notif
{
    MXGroup *group = notif.userInfo[kMXSessionNotificationGroupKey];
    if (group && [group.groupId isEqualToString:_group.groupId])
    {
        // Update the current displayed group instance with the one stored in the session.
        [self refreshDisplayWithGroup:group];
    }
}

- (void)refreshDisplayWithGroup:(MXGroup *)group
{
    _group = group;
    
    if (_group)
    {
        _searchBarHeader.hidden = NO;
        groupRooms = _group.rooms.chunk;
    }
    else
    {
        // Search bar header is hidden when no group is provided
        _searchBarHeader.hidden = YES;
        groupRooms = nil;
    }
    
    // Reload search result if any
    if (currentSearchText.length)
    {
        NSString *searchText = currentSearchText;
        currentSearchText = nil;
        
        [self searchBar:_searchBarView textDidChange:searchText];
    }
    else
    {
        [self refreshTableView];
    }
}

- (void)startActivityIndicator
{
    // Check whether the current view controller is displayed inside a segmented view controller in order to run the right activity view
    if (self.parentViewController && [self.parentViewController isKindOfClass:SegmentedViewController.class])
    {
        [((SegmentedViewController*)self.parentViewController) startActivityIndicator];
        
        // Force stop the activity view of the view controller
        [self.activityIndicator stopAnimating];
    }
    else
    {
        [super startActivityIndicator];
    }
}

- (void)stopActivityIndicator
{
    // Check whether the current view controller is displayed inside a segmented view controller in order to stop the right activity view
    if (self.parentViewController && [self.parentViewController isKindOfClass:SegmentedViewController.class])
    {
        [((SegmentedViewController*)self.parentViewController) stopActivityIndicator];
        
        // Force stop the activity view of the view controller
        [self.activityIndicator stopAnimating];
    }
    else
    {
        [super stopActivityIndicator];
    }
}

#pragma mark - Internals

- (void)refreshTableView
{
    [self.tableView reloadData];
}

- (void)pushViewController:(UIViewController*)viewController
{
    // Check whether the view controller is displayed inside a segmented one.
    if (self.parentViewController.navigationController)
    {
        // Hide back button title
        self.parentViewController.navigationItem.backBarButtonItem =[[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
        
        [self.parentViewController.navigationController pushViewController:viewController animated:YES];
    }
    else
    {
        // Hide back button title
        self.navigationItem.backBarButtonItem =[[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
        
        [self.navigationController pushViewController:viewController animated:YES];
    }
}

#pragma mark - UITableView data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger count = 0;
    
    if (currentSearchText.length)
    {
        if (filteredGroupRooms.count)
        {
            count++;
        }
    }
    else
    {
        if (groupRooms.count)
        {
            count++;
        }
    }
    
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = 0;
    
    if (currentSearchText.length)
    {
        count = filteredGroupRooms.count;
    }
    else
    {
        count = groupRooms.count;
    }
    
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    GroupRoomTableViewCell* roomCell = [tableView dequeueReusableCellWithIdentifier:@"RoomTableViewCellId" forIndexPath:indexPath];
    roomCell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    MXGroupRoom *room;
    NSArray *rooms;
    
    if (currentSearchText.length)
    {
        rooms = filteredGroupRooms;
    }
    else
    {
        rooms = groupRooms;
    }
    
    if (indexPath.row < rooms.count)
    {
        room = rooms[indexPath.row];
    }
    
    if (room)
    {
        [roomCell render:room withMatrixSession:self.mxSession];
    }
    
    return roomCell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath*)indexPath
{
    // iOS8 requires this method to enable editing (see editActionsForRowAtIndexPath).
}

#pragma mark - UITableView delegate

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return tableView.estimatedRowHeight;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell.backgroundColor = kRiotPrimaryBgColor;
    
    // Update the selected background view
    if (kRiotSelectedBgColor)
    {
        cell.selectedBackgroundView = [[UIView alloc] init];
        cell.selectedBackgroundView.backgroundColor = kRiotSelectedBgColor;
    }
    else
    {
        if (tableView.style == UITableViewStylePlain)
        {
            cell.selectedBackgroundView = nil;
        }
        else
        {
            cell.selectedBackgroundView.backgroundColor = nil;
        }
    }
    
    // Refresh here the estimated row height
    tableView.estimatedRowHeight = cell.frame.size.height;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

//- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    NSMutableArray* actions;
//
//    // @TODO Add the swipe to remove this room from the community if the current user is admin
//    actions = [[NSMutableArray alloc] init];
//
//    // Patch: Force the width of the button by adding whitespace characters into the title string.
//    UITableViewRowAction *leaveAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"        "  handler:^(UITableViewRowAction *action, NSIndexPath *indexPath){
//
//        // @TODO Remove the room
//
//    }];
//
//    leaveAction.backgroundColor = [MXKTools convertImageToPatternColor:@"remove_icon_blue" backgroundColor:kRiotSecondaryBgColor patternSize:CGSizeMake(74, 74) resourceSize:CGSizeMake(24, 24)];
//    [actions insertObject:leaveAction atIndex:0];
//
//    return actions;
//}

#pragma mark - UISearchBar delegate

- (void)refreshSearchBarItemsColor:(UISearchBar *)searchBar
{
    // bar tint color
    searchBar.barTintColor = searchBar.tintColor = kRiotColorBlue;
    searchBar.tintColor = kRiotColorBlue;
    
    // FIXME: this all seems incredibly fragile and tied to gutwrenching the current UISearchBar internals.
    
    // text color
    UITextField *searchBarTextField = [searchBar valueForKey:@"_searchField"];
    searchBarTextField.textColor = kRiotSecondaryTextColor;
    
    // Magnifying glass icon.
    UIImageView *leftImageView = (UIImageView *)searchBarTextField.leftView;
    leftImageView.image = [leftImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    leftImageView.tintColor = kRiotColorBlue;
    
    // remove the gray background color
    UIView *effectBackgroundTop =  [searchBarTextField valueForKey:@"_effectBackgroundTop"];
    UIView *effectBackgroundBottom =  [searchBarTextField valueForKey:@"_effectBackgroundBottom"];
    effectBackgroundTop.hidden = YES;
    effectBackgroundBottom.hidden = YES;
    
    // place holder
    searchBarTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:searchBarTextField.placeholder
                                                                               attributes:@{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                                                                            NSUnderlineColorAttributeName: kRiotColorBlue,
                                                                                            NSForegroundColorAttributeName: kRiotColorBlue}];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    // Update search results.
    NSUInteger index;
    MXGroupRoom *groupRoom;
    
    searchText = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (!currentSearchText.length || [searchText hasPrefix:currentSearchText] == NO)
    {
        // Copy participants and invited participants
        filteredGroupRooms = [NSMutableArray arrayWithArray:groupRooms];
    }
    
    currentSearchText = searchText;
    
    // Filter group participants
    if (currentSearchText.length)
    {
        for (index = 0; index < filteredGroupRooms.count;)
        {
            groupRoom = filteredGroupRooms[index];
            
            NSString *displayName = groupRoom.name;
            if (!displayName)
            {
                displayName = groupRoom.canonicalAlias;
            }
            if (!displayName)
            {
                displayName = groupRoom.roomId;
            }
            
            if ([displayName rangeOfString:currentSearchText options:NSCaseInsensitiveSearch].location == NSNotFound)
            {
                [filteredGroupRooms removeObjectAtIndex:index];
            }
            else
            {
                index++;
            }
        }
    }
    else
    {
        filteredGroupRooms = nil;
    }
    
    // Refresh display
    [self refreshTableView];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    searchBar.showsCancelButton = YES;
    
    return YES;
}

- (BOOL)searchBarShouldEndEditing:(UISearchBar *)searchBar
{
    searchBar.showsCancelButton = NO;
    
    return YES;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    // "Done" key has been pressed.
    
    // Dismiss keyboard
    [_searchBarView resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    if (currentSearchText)
    {
        currentSearchText = nil;
        filteredGroupRooms = nil;
        
        [self refreshTableView];
    }
    
    searchBar.text = nil;
    // Leave search
    [searchBar resignFirstResponder];
}

@end