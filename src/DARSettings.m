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
@interface DARLibraryController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic,strong) NSArray<NSURL *> *files;
@property(nonatomic,strong) AVAudioPlayer *player;
@end
@implementation DARLibraryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"音频库";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importAudio)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.toolbarItems=@[[[UIBarButtonItem alloc] initWithTitle:@"取消待发送音频" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAudio)]];
    [self.navigationController setToolbarHidden:NO]; [self reload];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.player stop]; }
- (void)reload { self.files=DARAudioLibrary.shared.files; [self.tableView reloadData]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)cancelAudio { [DARAudioLibrary.shared cancelPending]; DARToast(@"已取消待发送音频"); [self reload]; }
- (void)importAudio {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.delegate=self; picker.allowsMultipleSelection=YES; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(__unused UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for(NSURL *url in urls) {
        BOOL access=[url startAccessingSecurityScopedResource]; NSError *error;
        [DARAudioLibrary.shared importFile:url name:url.lastPathComponent error:&error];
        if(access)[url stopAccessingSecurityScopedResource]; if(error)DARToast(error.localizedDescription);
    } [self reload];
}
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return self.files.count; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section {
    return DARAudioLibrary.shared.armed?@"已准备下一条评论语音。返回评论区，录制约 1 秒后松开，发送已选音频。5 分钟内有效，仅使用一次。":@"点右上角导入音频，或长按视频选择“音频入库”。点文件可试听或准备为下一条评论语音，最长取前 29.5 秒。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"audio"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"audio"];
    NSURL *file=self.files[indexPath.row]; NSNumber *size; [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    cell.textLabel.text=file.lastPathComponent.stringByDeletingPathExtension;
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",file.pathExtension.uppercaseString,[NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSURL *file=self.files[indexPath.row];
    UIAlertController *actions=[UIAlertController alertControllerWithTitle:file.lastPathComponent.stringByDeletingPathExtension message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actions addAction:[UIAlertAction actionWithTitle:@"试听" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        [self.player stop]; NSError *error; self.player=[[AVAudioPlayer alloc] initWithContentsOfURL:file error:&error];
        if(error || ![self.player play])DARToast(@"无法播放该音频");
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"用于下一条评论语音" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        self.navigationItem.prompt=@"正在准备音频…";
        [DARAudioLibrary.shared prepareFile:file completion:^(NSError *error){
            self.navigationItem.prompt=nil; [self reload];
            if(error){DARToast(error.localizedDescription);return;}
            UIAlertController *ready=[UIAlertController alertControllerWithTitle:@"音频已准备" message:@"返回评论区，录制约 1 秒后松开，即可发送这段音频。仅替换下一次评论语音，5 分钟内有效。" preferredStyle:UIAlertControllerStyleAlert];
            [ready addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[self close];}]];
            [self presentViewController:ready animated:YES completion:nil];
        }];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
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
    return @[@"防撤回处理之后收到的消息；关闭标记会立即隐藏灰色标签。",@"在视频时间旁显示 IP 属地。切换后可滑到下一条视频查看。",@"长按视频可将音乐入库。音频库支持导入、试听、删除和准备下一条评论语音；待发送音频仅使用一次，最长取前 29.5 秒。",@"长按图文视频，选择保存当前原图或整组图片。使用服务端原图链接，需允许添加到相册。\nv0.2.0 · 适配抖音 41.2.0（412021）"][section];
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
