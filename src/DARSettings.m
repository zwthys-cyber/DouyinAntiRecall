#import "DARFeatures.h"
#import "DARAudio.h"
#import "DAROptions.h"
#import "DARRuntime.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

UIViewController *DARTopController(void) {
    UIWindow *window;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *candidate in ((UIWindowScene *)scene).windows)if(candidate.isKeyWindow){window=candidate;break;}
        if(window)break;
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
@interface DARLibraryController : UITableViewController <UIDocumentPickerDelegate, AVAudioPlayerDelegate>
@property(nonatomic,strong) NSArray<NSURL *> *files;
@property(nonatomic,strong) AVAudioPlayer *player;
@property(nonatomic,strong) NSURL *playingFile;
@property(nonatomic,strong) NSURL *preparingFile;
@property(nonatomic) NSUInteger prepareGeneration;
- (void)playFile:(NSURL *)file;
- (void)prepareFileForComment:(NSURL *)file;
@end
@implementation DARLibraryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"音频库";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importAudio)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.toolbarItems=@[[[UIBarButtonItem alloc] initWithTitle:@"取消待发送音频" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAudio)]];
    [self.navigationController setToolbarHidden:NO]; self.tableView.rowHeight=64; [self reload];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.player stop]; self.playingFile=nil; }
- (void)reload { self.files=DARAudioLibrary.shared.files; [self.tableView reloadData]; }
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
            [DARAudioLibrary.shared importFile:url name:url.lastPathComponent error:&error];
            if(access)[url stopAccessingSecurityScopedResource];if(error)[errors addObject:error.localizedDescription];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            self.navigationItem.prompt=nil;[self reload];
            DARToast(errors.count?errors.firstObject:@"音频已导入");
        });
    });
}
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return self.files.count; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section {
    return DARAudioLibrary.shared.armed?@"已准备下一条评论语音。返回评论区，录制约 1 秒后松开，发送已选音频。5 分钟内有效，仅使用一次。":@"右侧按钮可试听或发送。发送会先准备音频，随后回评论区录约 1 秒松开完成发送，最长取前 29.5 秒。点文件可打开更多操作。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"audio"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"audio"];
    NSURL *file=self.files[indexPath.row]; NSNumber *size; [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    cell.textLabel.text=file.lastPathComponent.stringByDeletingPathExtension;
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",file.pathExtension.uppercaseString,[NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
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
        if(!self.view.window || self.presentedViewController){DARToast(@"下一条评论音频已准备，回评论区录约 1 秒发送");return;}
        UIAlertController *ready=[UIAlertController alertControllerWithTitle:@"音频已准备" message:@"返回评论区，录制约 1 秒后松开，即可发送这段音频。仅替换下一次评论语音，5 分钟内有效。" preferredStyle:UIAlertControllerStyleAlert];
        [ready addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self close];}]];
        [self presentViewController:ready animated:YES completion:nil];
    }];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSURL *file=self.files[indexPath.row];
    UIAlertController *actions=[UIAlertController alertControllerWithTitle:file.lastPathComponent.stringByDeletingPathExtension message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actions addAction:[UIAlertAction actionWithTitle:@"试听" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self playFile:file];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"用于下一条评论语音" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self prepareFileForComment:file];}]];
    [actions addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        if([self.playingFile isEqual:file]){[self.player stop];self.playingFile=nil;}
        if([self.preparingFile isEqual:file]){self.prepareGeneration++;self.preparingFile=nil;self.navigationItem.prompt=nil;}
        NSError *error; [DARAudioLibrary.shared removeFile:file error:&error]; if(error)DARToast(error.localizedDescription); [self reload];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    actions.popoverPresentationController.sourceView=[tableView cellForRowAtIndexPath:indexPath];
    actions.popoverPresentationController.sourceRect=[tableView cellForRowAtIndexPath:indexPath].bounds;
    [self presentViewController:actions animated:YES completion:nil];
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
    @[@[@"视频音频入库",DAROptionAudioLibrary],@[@"评论区发送库内音频",DAROptionCommentAudio],@[@"打开音频库",@"library"]],
    @[@[@"无水印保存图片",DAROptionImages]]]; }
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView { return self.rows.count; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.rows[section] count]; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"消息",@"视频信息",@"音频",@"图片"][section]; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @[@"防撤回处理之后收到的消息；关闭标记会立即隐藏灰色标签。",@"在视频时间旁显示 IP 属地。切换后可滑到下一条视频查看。",@"长按视频可将音乐入库。音频库支持导入、试听、删除和准备下一条评论语音；待发送音频仅使用一次，最长取前 29.5 秒。",@"长按图文视频，选择保存当前原图或整组图片。使用服务端原图链接，有 EXIF 拍摄日期时按该日期存入相册；缺失时使用系统默认时间。需允许添加到相册。\nv0.2.3 · 适配抖音 41.2.0（412021）"][section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"option"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
    NSArray *row=self.rows[indexPath.section][indexPath.row]; cell.textLabel.text=row[0];
    if([row[1] isEqual:@"library"]) {cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
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
    BOOL settings=DARInstallSettingsHooks(), ip=DARInstallIPHooks(), menu=DARInstallMenuHooks(), audio=DARInstallAudioHooks();
    return settings&&ip&&menu&&audio;
}
