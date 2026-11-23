#import "DARFeatures.h"
#import "DARLoginDiagnostics.h"
#import "DARNotifications.h"
#import "DARPushBinding.h"
#import "DARAudio.h"
#import "DAROptions.h"
#import "DARRuntime.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <math.h>

UIViewController *DARTopController(void) {
    UIWindow *window;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *candidate in ((UIWindowScene *)scene).windows)if(candidate.isKeyWindow){window=candidate;break;}
        if(window)break;
    }
    // Apps using the UIApplicationDelegate lifecycle may have no connected scenes.
    if(!window) {
        id windows=DARGet(UIApplication.sharedApplication,@"windows");
        if([windows isKindOfClass:NSArray.class])for(UIWindow *candidate in windows)
            if(candidate.isKeyWindow){window=candidate;break;}
    }
    UIViewController *controller=window.rootViewController;
    for(NSUInteger i=0;i<20 && controller;i++) {
        if(controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)controller=controller.presentedViewController;
        else if([controller isKindOfClass:UINavigationController.class])controller=((UINavigationController *)controller).visibleViewController;
        else if([controller isKindOfClass:UITabBarController.class])controller=((UITabBarController *)controller).selectedViewController;
        else break;
    } return controller;
}
void DARToast(NSString *message) {
    dispatch_async(dispatch_get_main_queue(),^{
        UIView *view=DARTopController().view; if(!view)return;
        UILabel *label=[UILabel new]; label.text=message; label.numberOfLines=0;
        label.textAlignment=NSTextAlignmentCenter; label.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        label.textColor=UIColor.whiteColor; label.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.82];
        label.layer.cornerRadius=10; label.clipsToBounds=YES; label.translatesAutoresizingMaskIntoConstraints=NO;
        [view addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
            [label.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-40],
            [label.widthAnchor constraintLessThanOrEqualToAnchor:view.widthAnchor constant:-40],
            [label.heightAnchor constraintGreaterThanOrEqualToConstant:42]]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [UIView animateWithDuration:0.2 animations:^{label.alpha=0;} completion:^(__unused BOOL finished){[label removeFromSuperview];}];
        });
    });
}
@interface DARLibraryController : UITableViewController <UIDocumentPickerDelegate, AVAudioPlayerDelegate, UISearchBarDelegate>
@property(nonatomic,strong) NSArray<NSURL *> *files;
@property(nonatomic,strong) AVAudioPlayer *player;
@property(nonatomic,strong) NSURL *playingFile;
@property(nonatomic,strong) NSURL *preparingFile;
@property(nonatomic) NSUInteger prepareGeneration;
@property(nonatomic,strong) NSURL *currentDirectory;
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *durations;
@property(nonatomic) NSUInteger metadataGeneration;
@property(nonatomic,strong) UIBarButtonItem *deleteSelectedButton;
- (void)reload;
- (void)renameFile:(NSURL *)file;
- (void)shareFile:(NSURL *)file anchor:(UIView *)anchor;
- (void)deleteFiles:(NSArray<NSURL *> *)files;
- (void)playFile:(NSURL *)file;
- (void)prepareFileForComment:(NSURL *)file;
@end
@implementation DARLibraryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    if(!self.currentDirectory)self.currentDirectory=DARAudioLibrary.shared.directory;
    self.title=[self.currentDirectory isEqual:DARAudioLibrary.shared.directory]?@"音频助手":self.currentDirectory.lastPathComponent;
    self.overrideUserInterfaceStyle=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    self.durations=[NSMutableDictionary new];
    UIBarButtonItem *folder=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain target:self action:@selector(addFolder)];folder.accessibilityLabel=@"新建文件夹";
    UIBarButtonItem *import=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(importAudio)];import.accessibilityLabel=@"导入音频";
    self.navigationItem.rightBarButtonItems=@[folder,import,self.editButtonItem];
    if([self.currentDirectory isEqual:DARAudioLibrary.shared.directory])self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.deleteSelectedButton=[[UIBarButtonItem alloc] initWithTitle:@"删除所选 (0)" style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];self.deleteSelectedButton.tintColor=UIColor.systemRedColor;self.deleteSelectedButton.enabled=NO;
    self.toolbarItems=@[[[UIBarButtonItem alloc] initWithTitle:@"取消待发送音频" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAudio)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],self.deleteSelectedButton];
    self.searchBar=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,320,56)];self.searchBar.placeholder=@"搜索音频文件";self.searchBar.delegate=self;self.searchBar.searchBarStyle=UISearchBarStyleMinimal;self.searchBar.accessibilityIdentifier=@"DAR.audio.search";
    self.tableView.tableHeaderView=self.searchBar;
    self.tableView.allowsMultipleSelectionDuringEditing=YES;self.tableView.rowHeight=72;
    [self.navigationController setToolbarHidden:NO];[self reload];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];[self.navigationController setToolbarHidden:NO];[self reload]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.player stop]; self.playingFile=nil; }
- (BOOL)isFolder:(NSURL *)file {NSNumber *value;[file getResourceValue:&value forKey:NSURLIsDirectoryKey error:NULL];return value.boolValue;}
- (void)updateSelection {
    NSUInteger count=self.tableView.indexPathsForSelectedRows.count;
    self.deleteSelectedButton.title=[NSString stringWithFormat:@"删除所选 (%lu)",(unsigned long)count];self.deleteSelectedButton.enabled=count>0;
}
- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];self.searchBar.userInteractionEnabled=!editing;
    [self.tableView reloadData];[self updateSelection];
}
- (void)reload {
    NSArray<NSURL *> *all=[DARAudioLibrary.shared itemsInDirectory:self.currentDirectory];
    NSString *query=self.searchBar.text?:@"";
    self.files=query.length?[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url,__unused NSDictionary *bindings){return [url.lastPathComponent localizedCaseInsensitiveContainsString:query];}]]:all;
    UILabel *empty=[UILabel new];empty.text=query.length?@"没有匹配的文件":@"暂无音频，点右上角导入或新建文件夹";empty.numberOfLines=0;empty.textAlignment=NSTextAlignmentCenter;empty.textColor=UIColor.secondaryLabelColor;
    self.tableView.backgroundView=self.files.count?nil:empty;
    [self.tableView reloadData];[self updateSelection];
    NSUInteger generation=++self.metadataGeneration;NSArray<NSURL *> *snapshot=self.files;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSMutableDictionary *values=[NSMutableDictionary new];
        for(NSURL *url in snapshot)if(![self isFolder:url]){
            NSTimeInterval seconds=CMTimeGetSeconds([AVURLAsset URLAssetWithURL:url options:nil].duration);
            if(isfinite(seconds)&&seconds>0)values[url.path]=@(seconds);
        }
        dispatch_async(dispatch_get_main_queue(),^{if(generation==self.metadataGeneration){self.durations=values;if(!self.editing){[self.tableView reloadData];[self updateSelection];}}});
    });
}
- (void)searchBar:(__unused UISearchBar *)searchBar textDidChange:(__unused NSString *)searchText {[self reload];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {[searchBar resignFirstResponder];}
- (void)addFolder {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"新建文件夹" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"文件夹名称";}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){NSError *error;[DARAudioLibrary.shared createFolder:alert.textFields.firstObject.text inDirectory:self.currentDirectory error:&error];if(error)DARToast(error.localizedDescription);[self reload];}]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)cancelAudio {
    self.prepareGeneration++; self.preparingFile=nil; self.navigationItem.prompt=nil;
    [DARAudioLibrary.shared cancelPending]; DARToast(@"已取消待发送音频"); [self reload];
}
- (void)importAudio {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.delegate=self; picker.allowsMultipleSelection=YES; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(__unused UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    self.navigationItem.prompt=@"正在导入音频…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSMutableArray *errors=[NSMutableArray new];
        for(NSURL *url in urls) {
            BOOL access=[url startAccessingSecurityScopedResource];NSError *error;
            [DARAudioLibrary.shared importFile:url name:url.lastPathComponent intoDirectory:self.currentDirectory error:&error];
            if(access)[url stopAccessingSecurityScopedResource];if(error)[errors addObject:error.localizedDescription];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            self.navigationItem.prompt=nil;[self reload];
            DARToast(errors.count?errors.firstObject:@"音频已导入");
        });
    });
}
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return self.files.count; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(__unused NSInteger)section {
    unsigned long long bytes=0;NSUInteger folders=0;
    for(NSURL *url in self.files)if([self isFolder:url])folders++;else{NSNumber *size;[url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];bytes+=size.unsignedLongLongValue;}
    return [NSString stringWithFormat:@"%lu 个音频 · %lu 个文件夹 · %@",(unsigned long)(self.files.count-folders),(unsigned long)folders,[NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile]];
}
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section {
    return DARAudioLibrary.shared.armed?@"已准备下一条评论语音。返回评论区，手动录音后松开发送，评论时长默认跟随录音时长，音频内容不裁剪。5 分钟内有效，仅使用一次。":@"右侧按钮可试听或发送。发送会先准备音频，随后回评论区录音松开发送。评论时长默认跟随手动录音，音频内容保留原时长。点文件可打开更多操作。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"audio"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"audio"];
    NSURL *file=self.files[indexPath.row]; NSNumber *size; [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    BOOL folder=[self isFolder:file];
    cell.imageView.image=[UIImage systemImageNamed:folder?@"folder.fill":@"waveform"];
    cell.imageView.tintColor=folder?UIColor.systemOrangeColor:UIColor.systemBlueColor;
    cell.textLabel.text=folder?file.lastPathComponent:file.lastPathComponent.stringByDeletingPathExtension;
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",file.pathExtension.uppercaseString,[NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
    NSNumber *seconds=self.durations[file.path];
    if(seconds)cell.detailTextLabel.text=[cell.detailTextLabel.text stringByAppendingFormat:@" · %.1f 秒",seconds.doubleValue];
    if(folder){cell.detailTextLabel.text=@"文件夹";cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
    if(self.editing){cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryNone;return cell;}
    cell.textLabel.numberOfLines=1; cell.textLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    __weak typeof(self) weakSelf=self;
    UIButton *play=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *playStyle=[UIButtonConfiguration plainButtonConfiguration];
    BOOL playing=[self.playingFile isEqual:file] && self.player.isPlaying;
    playStyle.image=[UIImage systemImageNamed:playing?@"pause.fill":@"play.fill"];
    play.configuration=playStyle; play.accessibilityIdentifier=@"DAR.audio.play";
    play.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",playing?@"停止试听":@"试听",file.lastPathComponent];
    [play addAction:[UIAction actionWithHandler:^(__unused UIAction *action){[weakSelf playFile:file];}] forControlEvents:UIControlEventTouchUpInside];
    UIButton *send=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *sendStyle=[UIButtonConfiguration borderedProminentButtonConfiguration];
    sendStyle.title=@"发送"; sendStyle.buttonSize=UIButtonConfigurationSizeSmall;
    sendStyle.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
    sendStyle.showsActivityIndicator=[self.preparingFile isEqual:file]; send.configuration=sendStyle;
    send.enabled=self.preparingFile==nil; send.accessibilityIdentifier=@"DAR.audio.send";
    send.accessibilityLabel=[NSString stringWithFormat:@"准备发送 %@",file.lastPathComponent];
    [send addAction:[UIAction actionWithHandler:^(__unused UIAction *action){[weakSelf prepareFileForComment:file];}] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons=[[UIStackView alloc] initWithArrangedSubviews:@[play,send]];
    buttons.axis=UILayoutConstraintAxisHorizontal; buttons.spacing=8; buttons.alignment=UIStackViewAlignmentCenter;
    buttons.frame=CGRectMake(0,0,116,44);
    [NSLayoutConstraint activateConstraints:@[[play.widthAnchor constraintEqualToConstant:44],
        [play.heightAnchor constraintEqualToConstant:44],[send.widthAnchor constraintEqualToConstant:64],
        [send.heightAnchor constraintEqualToConstant:44]]];
    cell.accessoryType=UITableViewCellAccessoryNone;cell.accessoryView=buttons; return cell;
}
- (void)playFile:(NSURL *)file {
    if([self.playingFile isEqual:file] && self.player.isPlaying) {
        [self.player stop]; self.playingFile=nil;
    } else {
        [self.player stop]; NSError *error;
        self.player=[[AVAudioPlayer alloc] initWithContentsOfURL:file error:&error]; self.player.delegate=self;
        if(error || ![self.player play]) {self.playingFile=nil;DARToast(@"无法播放该音频");}
        else self.playingFile=file;
    }
    [self.tableView reloadData];
}
- (void)audioPlayerDidFinishPlaying:(__unused AVAudioPlayer *)player successfully:(__unused BOOL)success {
    self.playingFile=nil; [self.tableView reloadData];
}
- (void)prepareFileForComment:(NSURL *)file {
    if(self.preparingFile){DARToast(@"音频正在准备，请稍候");return;}
    [self.player stop]; self.playingFile=nil;
    self.preparingFile=file; NSUInteger generation=++self.prepareGeneration;
    self.navigationItem.prompt=@"正在准备音频…"; [self.tableView reloadData];
    __weak typeof(self) weakSelf=self;
    [DARAudioLibrary.shared prepareFile:file completion:^(NSError *error){
        DARLibraryController *self=weakSelf;
        if(!self || generation!=self.prepareGeneration)return;
        self.preparingFile=nil; self.navigationItem.prompt=nil; [self reload];
        if(error){DARToast(error.localizedDescription);return;}
        if(!self.view.window || self.presentedViewController){DARToast(@"下一条评论音频已准备，回评论区手动录音松开发送");return;}
        UIAlertController *ready=[UIAlertController alertControllerWithTitle:@"音频已准备" message:@"返回评论区手动录音后松开。默认使用本次手动录音的评论时长，音频文件保留原长度；关闭“评论时长跟随手动录音”可使用库内音频时长。仅替换下一次评论语音，5 分钟内有效。" preferredStyle:UIAlertControllerStyleAlert];
        [ready addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self close];}]];
        [self presentViewController:ready animated:YES completion:nil];
    }];
}
- (void)stopForFile:(NSURL *)file {
    NSString *path=file.path;
    if([self.playingFile.path isEqual:path] || [self.playingFile.path hasPrefix:[path stringByAppendingString:@"/"]]){[self.player stop];self.playingFile=nil;}
    if([self.preparingFile.path isEqual:path] || [self.preparingFile.path hasPrefix:[path stringByAppendingString:@"/"]]){self.prepareGeneration++;self.preparingFile=nil;self.navigationItem.prompt=nil;}
}
- (void)renameFile:(NSURL *)file {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"重命名" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=file.lastPathComponent;}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){NSError *error;NSURL *renamed=[DARAudioLibrary.shared renameItem:file name:alert.textFields.firstObject.text error:&error];if(renamed)[self stopForFile:file];if(error)DARToast(error.localizedDescription);[self reload];}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)shareFile:(NSURL *)file anchor:(UIView *)anchor {
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.popoverPresentationController.sourceView=anchor?:self.view;share.popoverPresentationController.sourceRect=anchor?anchor.bounds:CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    [self presentViewController:share animated:YES completion:nil];
}
- (void)deleteFiles:(NSArray<NSURL *> *)files {
    if(!files.count)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"删除所选文件？" message:@"删除文件夹也会删除其中的音频，此操作无法撤销。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        NSMutableArray *errors=[NSMutableArray new];
        for(NSURL *file in files){NSError *error;if([DARAudioLibrary.shared removeFile:file error:&error])[self stopForFile:file];if(error)[errors addObject:error.localizedDescription];}
        if(errors.count)DARToast(errors.firstObject);[self setEditing:NO animated:YES];[self reload];
    }]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)deleteSelected {
    NSMutableArray *selected=[NSMutableArray new];for(NSIndexPath *index in self.tableView.indexPathsForSelectedRows)if(index.row<(NSInteger)self.files.count)[selected addObject:self.files[index.row]];
    [self deleteFiles:selected];
}
- (void)tableView:(__unused UITableView *)tableView didDeselectRowAtIndexPath:(__unused NSIndexPath *)indexPath {[self updateSelection];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(self.editing){[self updateSelection];return;}
    [tableView deselectRowAtIndexPath:indexPath animated:YES];NSURL *file=self.files[indexPath.row];
    if([self isFolder:file]){DARLibraryController *next=[DARLibraryController new];next.currentDirectory=file;[self.navigationController pushViewController:next animated:YES];return;}
    UIView *anchor=[tableView cellForRowAtIndexPath:indexPath];
    UIAlertController *actions=[UIAlertController alertControllerWithTitle:file.lastPathComponent message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actions addAction:[UIAlertAction actionWithTitle:@"试听" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self playFile:file];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"用于下一条评论语音" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self prepareFileForComment:file];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self renameFile:file];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self shareFile:file anchor:anchor];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){[self deleteFiles:@[file]];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    actions.popoverPresentationController.sourceView=anchor;actions.popoverPresentationController.sourceRect=anchor.bounds;
    [self presentViewController:actions animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSURL *file=self.files[indexPath.row];UIView *anchor=[tableView cellForRowAtIndexPath:indexPath];
    UIContextualAction *rename=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"重命名" handler:^(__unused UIContextualAction *action,__unused UIView *view,void(^done)(BOOL)){done(YES);[self renameFile:file];}];
    UIContextualAction *remove=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(__unused UIContextualAction *action,__unused UIView *view,void(^done)(BOOL)){done(YES);[self deleteFiles:@[file]];}];
    NSMutableArray *actions=[NSMutableArray arrayWithObjects:remove,rename,nil];
    if(![self isFolder:file]){UIContextualAction *share=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"分享" handler:^(__unused UIContextualAction *action,__unused UIView *view,void(^done)(BOOL)){done(YES);[self shareFile:file anchor:anchor];}];share.backgroundColor=UIColor.systemPurpleColor;[actions addObject:share];}
    UISwipeActionsConfiguration *config=[UISwipeActionsConfiguration configurationWithActions:actions];config.performsFirstActionWithFullSwipe=NO;return config;
}

@end
void DAROpenAudioLibrary(UIViewController *presenter) {
    if(!presenter)presenter=DARTopController(); if(!presenter)return;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:[DARLibraryController new]];
    navigation.modalPresentationStyle=UIModalPresentationPageSheet; [presenter presentViewController:navigation animated:YES completion:nil];
}
@interface DARSettingsController : UITableViewController
@end
@implementation DARSettingsController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"抖音增强";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSArray *)rows { return @[
    @[@[@"消息防撤回",DAROptionAntiRecall],@[@"显示已撤回标记",DAROptionBadge]],
    @[@[@"显示 IP 属地",DAROptionIP]],
    @[@[@"视频音频入库",DAROptionAudioLibrary],@[@"评论区发送库内音频",DAROptionCommentAudio],@[@"评论时长跟随手动录音",DAROptionManualAudioDuration],@[@"打开音频助手",@"library"]],
    @[@[@"无水印保存图文",DAROptionImages],@[@"评论图片无水印",DAROptionCommentImages]],
    @[@[@"查看登录诊断",@"diagnostics"],@[@"消息通知修复",@"notifications"]]]; }
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView { return self.rows.count; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.rows[section] count]; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"消息",@"视频信息",@"音频",@"图片",@"诊断"][section]; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @[@"防撤回处理之后收到的消息；关闭标记会立即隐藏灰色标签。",@"在视频时间旁显示 IP 属地。切换后可滑到下一条视频查看。",@"长按视频可将音乐入库。音频库支持导入、试听、删除和准备下一条评论语音；待发送音频仅使用一次。默认评论时长跟随手动录音，音频内容保留原时长、不截断。",@"长按图文视频，选择保存当前原图或整组图片。使用服务端原图链接，有有效拍摄日期时按该日期存入相册；缺失时使用系统默认时间。评论图片开关让原生保存使用原图地址；图片像素本身已有水印无法移除。需允许添加到相册。",@"消息通知修复可申请权限、重新发起推送注册、测试本地提醒；不保证重签身份的远程消息能送达。登录诊断仅保留最近 16 条错误码和处理路径，重启清空。诊断入口位于本设置页，不显示悬浮按钮。\nv0.2.12 · 适配抖音 41.2.0（412021）"][section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"option"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
    NSArray *row=self.rows[indexPath.section][indexPath.row]; cell.textLabel.text=row[0];
    if([row[1] isEqual:@"library"] || [row[1] isEqual:@"diagnostics"] || [row[1] isEqual:@"notifications"]) {cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
    else {
        cell.accessoryType=UITableViewCellAccessoryNone; cell.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *toggle=[UISwitch new]; toggle.accessibilityIdentifier=row[1]; toggle.on=DAROptionEnabled(row[1]);
        [toggle addTarget:self action:@selector(changeOption:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle;
    } return cell;
}
- (void)changeOption:(UISwitch *)toggle { DARSetOption(toggle.accessibilityIdentifier,toggle.on); }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if([self.rows[indexPath.section][indexPath.row][1] isEqual:@"library"])DAROpenAudioLibrary(self);
    else if([self.rows[indexPath.section][indexPath.row][1] isEqual:@"diagnostics"])DAROpenLoginDiagnostics(self);
    else if([self.rows[indexPath.section][indexPath.row][1] isEqual:@"notifications"])DAROpenNotificationRepair(self);
}
@end
void DAROpenSettings(UIViewController *presenter) {
    if(!presenter)presenter=DARTopController(); if(!presenter)return;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:[DARSettingsController new]];
    navigation.modalPresentationStyle=UIModalPresentationPageSheet; [presenter presentViewController:navigation animated:YES completion:nil];
}
static IMP DAROriginalSettingsSections;
static char DARSettingsSection;
NSArray *DARAugmentSettingsSections(NSArray *sections,id viewModel) {
    if(![sections isKindOfClass:NSArray.class])return sections;
    for(id section in sections)if([DARGet(section,@"identifier") isEqual:@"dar.plugin.section"])return sections;
    id section=objc_getAssociatedObject(viewModel,&DARSettingsSection);
    if(!section) {
        id item=[[NSClassFromString(@"AWESettingItemModel") alloc] init];
        section=[[NSClassFromString(@"AWESettingSectionModel") alloc] init];
        if(!item||!section)return sections;
        DARPut(item,@"setIdentifier:",@"dar.plugin.settings"); DARPut(item,@"setTitle:",@"抖音增强");
        DARPut(item,@"setSubTitle:",@"消息 · 属地 · 音频 · 原图"); DARPutNumber(item,@"setCellType:",26);
        DARPutNumber(item,@"setIsEnable:",YES); DARPut(item,@"setSvgIconImageName:",@"ic_gearsimplify_outlined_20");
        __weak id weakModel=viewModel;
        DARPut(item,@"setCellTappedBlock:",^{ id delegate=DARGet(weakModel,@"controllerDelegate"); DAROpenSettings([delegate isKindOfClass:UIViewController.class]?delegate:nil); });
        DARPut(section,@"setIdentifier:",@"dar.plugin.section"); DARPut(section,@"setItemArray:",@[item]);
        objc_setAssociatedObject(viewModel,&DARSettingsSection,section,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [@[section] arrayByAddingObjectsFromArray:sections];
}
static id DARSettingsSections(id self,SEL selector) {
    id original=((id(*)(id,SEL))DAROriginalSettingsSections)(self,selector);
    return DARAugmentSettingsSections(original,self);
}
BOOL DARInstallSettingsHooks(void) {
    return DARHook(NSClassFromString(@"AWESettingsViewModel"),@"sectionDataArray",(IMP)DARSettingsSections,&DAROriginalSettingsSections,"@",2);
}
BOOL DARInstallFeatures(void) {
    BOOL settings=DARInstallSettingsHooks(), ip=DARInstallIPHooks(), menu=DARInstallMenuHooks(), audio=DARInstallAudioHooks(), commentImages=DARInstallCommentImageHooks();
    (void)DARInstallLoginDiagnostics();
    (void)DARInstallPushBindingObservers();
    return settings&&ip&&menu&&audio&&commentImages;
}
