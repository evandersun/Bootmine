//
//  DOMainViewController.m
//  Bootmine
//
//  Created by tomt000 on 08/01/2024.
//
//  Modified for roothide fork:
//    - Bootstrap-style home screen: a 2x2 grid of four action buttons with a
//      persistent log view underneath.
//    - New preference "noAutoRebootUserspace": when enabled, a successful
//      jailbreak no longer calls [DOJailbreaker finalize] (userspace reboot).
//

#import "DOMainViewController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import "DOJailbreaker.h"
#import "DOGlobalAppearance.h"
#import "DOThemeManager.h"
#import "DOPkgManagerPickerView.h"
#import "DOUpdateViewController.h"
#import "DOLogCrashViewController.h"
#import "DOPreferenceManager.h"
#import <pthread.h>
#import <sys/sysctl.h>
#import <libjailbreak/libjailbreak.h>

#pragma mark - Persistent log view (Bootstrap-style)

// A lightweight, always-on log view shown on the home screen.
// It intentionally is NOT a DODebugLogView subclass: DOUIManager only forwards
// debug (stdout/stderr) entries to DODebugLogView, so this view receives the
// clean, high-level progress messages (e.g. "Exploiting Kernel", "Bypassing
// PAC") which is exactly what a Bootstrap-style log console should show.
@interface DOBootstrapLogView : UIView <DOLogViewProtocol>
@property (nonatomic, strong) UITextView *textView;
@end

@implementation DOBootstrapLogView

- (instancetype)init
{
    if (self = [super init]) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        self.layer.cornerRadius = 14;
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _textView = [[UITextView alloc] init];
        _textView.translatesAutoresizingMaskIntoConstraints = NO;
        _textView.backgroundColor = [UIColor clearColor];
        _textView.textColor = [UIColor whiteColor];
        _textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        _textView.editable = NO;
        _textView.scrollEnabled = YES;
        _textView.textContainerInset = UIEdgeInsetsMake(10, 12, 10, 12);
        [self addSubview:_textView];

        [NSLayoutConstraint activateConstraints:@[
            [_textView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_textView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_textView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_textView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)showLog:(NSString *)log
{
    if (!log) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = [self.textView.text stringByAppendingFormat:@"> %@\n", log];
        [UIView performWithoutAnimation:^{
            [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
        }];
    });
}

- (void)didComplete
{
    // Nothing to do: completion is handled by the view controller.
}

@end

#pragma mark - Main view controller

@interface DOMainViewController ()

@property (nonatomic, strong) DOBootstrapLogView *logView;
@property (nonatomic, strong) UIView *buttonsContainer;
@property (nonatomic, strong) UIButton *jailbreakGridButton;
@property (nonatomic, strong) NSArray<UIButton *> *actionButtons;
@property (nonatomic, strong) DOPkgManagerPickerView *pkgManagerPickerView;
@property(nonatomic) BOOL hideStatusBar;
@property(nonatomic) BOOL hideHomeIndicator;

@end

@implementation DOMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupStack];
}

#pragma mark - Layout

-(void)setupStack
{
    // Main vertical stack
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.spacing = 18;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stackView];

    UILayoutGuide *safeGuide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:safeGuide.topAnchor constant:16],
        [stackView.bottomAnchor constraintEqualToAnchor:safeGuide.bottomAnchor constant:-8],
    ]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        NSLayoutConstraint *relativeWidthConstraint = [stackView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8];
        relativeWidthConstraint.priority = UILayoutPriorityDefaultHigh;
        NSLayoutConstraint *maxWidthConstraint = [stackView.widthAnchor constraintLessThanOrEqualToConstant:UI_IPAD_MAX_WIDTH];
        maxWidthConstraint.priority = UILayoutPriorityRequired;

        [NSLayoutConstraint activateConstraints:@[
            relativeWidthConstraint,
            maxWidthConstraint,
            [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
        ]];
    }
    else
    {
        [NSLayoutConstraint activateConstraints:@[
            [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:UI_PADDING],
            [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-UI_PADDING],
        ]];
    }

    // Header
    DOHeaderView *headerView = [[DOHeaderView alloc] initWithImage:[UIImage imageNamed:@"Bootmine"] subtitles: @[
        [DOGlobalAppearance mainSubtitleString:[[DOEnvironmentManager sharedManager] versionSupportString]],
        [DOGlobalAppearance secondarySubtitleString:DOLocalizedString(@"Credits_Made_By")],
    ]];
    [stackView addArrangedSubview:headerView];
    [headerView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    // Four action buttons in a 2x2 grid (Bootstrap style)
    UIView *buttonsContainer = [[UIView alloc] init];
    buttonsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView addArrangedSubview:buttonsContainer];
    self.buttonsContainer = buttonsContainer;

    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.distribution = UIStackViewDistributionFillEqually;
    grid.spacing = 12;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonsContainer addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:buttonsContainer.leadingAnchor],
        [grid.trailingAnchor constraintEqualToAnchor:buttonsContainer.trailingAnchor],
        [grid.topAnchor constraintEqualToAnchor:buttonsContainer.topAnchor],
        [grid.bottomAnchor constraintEqualToAnchor:buttonsContainer.bottomAnchor],
        [grid.heightAnchor constraintEqualToConstant:150],
    ]];

    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken] || [[DOEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];

    UIButton *jailbreakButton = [self gridButtonWithTitle:[self jailbreakButtonTitle]
                                               imageName:isSupported ? @"lock.open" : @"lock.slash"
                                              identifier:@"jailbreak"
                                                 enabled:(!isJailbroken && isSupported)];
    self.jailbreakGridButton = jailbreakButton;

    UIButton *settingsButton = [self gridButtonWithTitle:DOLocalizedString(@"Menu_Settings_Title")
                                              imageName:@"gearshape"
                                             identifier:@"settings"
                                                enabled:YES];

    UIButton *rebootButton = [self gridButtonWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title")
                                            imageName:@"arrow.clockwise.circle"
                                           identifier:@"reboot-userspace"
                                              enabled:isJailbroken];

    UIButton *creditsButton = [self gridButtonWithTitle:DOLocalizedString(@"Menu_Credits_Title")
                                             imageName:@"info.circle"
                                            identifier:@"credits"
                                               enabled:YES];
    self.actionButtons = @[jailbreakButton, settingsButton, rebootButton, creditsButton];

    UIStackView *row1 = [[UIStackView alloc] initWithArrangedSubviews:@[jailbreakButton, settingsButton]];
    row1.axis = UILayoutConstraintAxisHorizontal;
    row1.distribution = UIStackViewDistributionFillEqually;
    row1.spacing = 12;

    UIStackView *row2 = [[UIStackView alloc] initWithArrangedSubviews:@[rebootButton, creditsButton]];
    row2.axis = UILayoutConstraintAxisHorizontal;
    row2.distribution = UIStackViewDistributionFillEqually;
    row2.spacing = 12;

    [grid addArrangedSubview:row1];
    [grid addArrangedSubview:row2];

    // Persistent log view at the bottom
    UIView *logContainer = [[UIView alloc] init];
    logContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [logContainer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [logContainer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [stackView addArrangedSubview:logContainer];

    DOBootstrapLogView *logView = [[DOBootstrapLogView alloc] init];
    logView.translatesAutoresizingMaskIntoConstraints = NO;
    [logContainer addSubview:logView];
    [NSLayoutConstraint activateConstraints:@[
        [logView.leadingAnchor constraintEqualToAnchor:logContainer.leadingAnchor],
        [logView.trailingAnchor constraintEqualToAnchor:logContainer.trailingAnchor],
        [logView.topAnchor constraintEqualToAnchor:logContainer.topAnchor],
        [logView.bottomAnchor constraintEqualToAnchor:logContainer.bottomAnchor],
    ]];
    self.logView = logView;
    [[DOUIManager sharedInstance] setLogView:logView];

    [[DOUIManager sharedInstance] sendLog:DOLocalizedString(@"Log_Ready") debug:NO];
}

// Builds one Bootstrap-style grid button (icon on top, label underneath).
- (UIButton *)gridButtonWithTitle:(NSString *)title
                        imageName:(NSString *)imageName
                       identifier:(NSString *)identifier
                          enabled:(BOOL)enabled
{
    UIImage *image = [UIImage systemImageNamed:imageName withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]];
    UIAction *action = [UIAction actionWithTitle:title image:image identifier:identifier handler:^(__kindof UIAction * _Nonnull action) {
        [self gridButtonTapped:action];
    }];

    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.background.backgroundColor = [DOThemeManager menuColorWithAlpha:1.0];
    config.background.cornerRadius = 14;
    config.background.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    config.baseForegroundColor = [UIColor whiteColor];
    config.imagePadding = 8;
    config.imagePlacement = NSDirectionalRectPlacementTop;
    config.titleLineBreakMode = NSLineBreakByTruncatingTail;

    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:action];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.enabled = enabled;
    return button;
}

#pragma mark - Button actions

- (void)gridButtonTapped:(UIAction *)action
{
    NSString *identifier = action.identifier;
    if ([identifier isEqualToString:@"settings"]) {
        [self.navigationController pushViewController:[[DOSettingsController alloc] init] animated:YES];
    }
    else if ([identifier isEqualToString:@"credits"]) {
        [self.navigationController pushViewController:[[DOCreditsViewController alloc] init] animated:YES];
    }
    else if ([identifier isEqualToString:@"reboot-userspace"]) {
        if ([[DOEnvironmentManager sharedManager] isJailbroken]) {
            [self fadeToBlack:^{
                [[DOEnvironmentManager sharedManager] rebootUserspace];
            }];
        }
    }
    else if ([identifier isEqualToString:@"jailbreak"]) {
        [self handleJailbreakTap];
    }
}

- (void)handleJailbreakTap
{
/********************************** roothide specific ************************************/
    if(otherJailbreakActived(false)) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Error") message:DOLocalizedString(@"Your device currently has another jailbreak activated, please reboot device.") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        }];
        [alertController addAction:rebootAction];
        [self presentViewController:alertController animated:YES completion:nil];
        return;
    }
/********************************** roothide specific ************************************/

    // Disable all buttons while jailbreaking.
    [UIView animateWithDuration:0.25 animations:^{
        for (UIButton *button in self.actionButtons) {
            button.enabled = NO;
        }
    }];

    // If no package manager has been selected yet, ask first, then jailbreak.
    if ([[DOUIManager sharedInstance] enabledPackageManagerKeys].count == 0)
    {
        __weak typeof(self) weakSelf = self;
        self.pkgManagerPickerView = [[DOPkgManagerPickerView alloc] initWithCallback:^(BOOL success) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.pkgManagerPickerView removeFromSuperview];
            strongSelf.pkgManagerPickerView = nil;
            [strongSelf startJailbreak];
        }];

        self.pkgManagerPickerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.pkgManagerPickerView];
        [NSLayoutConstraint activateConstraints:@[
            [self.pkgManagerPickerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.pkgManagerPickerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.pkgManagerPickerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [self.pkgManagerPickerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];
    }
    else
    {
        [self startJailbreak];
    }
}

- (NSString *)jailbreakButtonTitle
{
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];
    BOOL removeJailbreakEnabled = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"removeJailbreakEnabled" fallback:NO];

    NSString *jailbreakButtonTitle = DOLocalizedString(@"Button_Jailbreak_Title");
    if (!isSupported)
        jailbreakButtonTitle = DOLocalizedString(@"Unsupported");
    else if (isJailbroken)
        jailbreakButtonTitle = DOLocalizedString(@"Status_Title_Jailbroken");
    else if (removeJailbreakEnabled)
        jailbreakButtonTitle = DOLocalizedString(@"Button_Remove_Jailbreak");

    return jailbreakButtonTitle;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.jailbreakGridButton setTitle:[self jailbreakButtonTitle] forState:UIControlStateNormal];
}

#pragma mark - Jailbreak

- (void)startJailbreak
{
    DOJailbreaker *jailbreaker = [[DOJailbreaker alloc] init];

    [[DOUIManager sharedInstance] startLogCapture];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if ([jailbreaker contiguousMappingWorkaroundNeeded]) {

            cpu_subtype_t cpuFamily = 0;
            size_t cpuFamilySize = sizeof(cpuFamily);
            sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
            NSString *workaroundMessage = DOLocalizedString(@"Respring_Required_Message");
            if (cpuFamily == CPUFAMILY_ARM_TYPHOON) {
                workaroundMessage = [workaroundMessage stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", DOLocalizedString(@"Respring_Required_Notice_A8")]];
            }

            UIAlertController *contiguousMappingWorkaroundAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Respring_Required") message:workaroundMessage preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Respring_Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }];

            UIAlertAction *workaroundAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Apply_Workaround") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [jailbreaker applyContiguousMappingWorkaround];
            }];

            [contiguousMappingWorkaroundAlertController addAction:cancelAction];
            [contiguousMappingWorkaroundAlertController addAction:workaroundAction];
            contiguousMappingWorkaroundAlertController.preferredAction = workaroundAction;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:contiguousMappingWorkaroundAlertController animated:YES completion:nil];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.hideHomeIndicator = YES;
        });

        NSError *error;
        BOOL didRemove = NO;
        BOOL showLogs = YES;
        [jailbreaker runWithError:&error didRemoveJailbreak:&didRemove showLogs:&showLogs];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error && showLogs) {
                [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"Jailbreak failed with error: %@", error] debug:NO];
                [self.navigationController pushViewController:[[DOLogCrashViewController alloc] initWithTitle:[error localizedDescription]] animated:YES];
            }
            else if (error && !showLogs) {
                // Used when there is an error that is explainable in such detail that additional logs are not needed
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Log_Error") message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Reboot") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exec_cmd_trusted(JBROOT_PATH("/sbin/reboot"), NULL);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else if (didRemove) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Removed_Jailbreak_Alert_Title") message:DOLocalizedString(@"Removed_Jailbreak_Alert_Message") preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else {
                // No errors
                [[DOUIManager sharedInstance] completeJailbreak];

                /**************** roothide specific: configurable userspace reboot ****************/
                BOOL noAutoReboot = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"noAutoRebootUserspace" fallback:NO];
                if (noAutoReboot) {
                    // Keep the app on screen; user chooses when to reboot userspace.
                    [self showJailbreakDoneWithoutReboot];
                } else {
                    [self fadeToBlack: ^{
                        [jailbreaker finalize];
                    }];
                }
                /********************************************************************************/
            }
        });
    });
}

// Presented when "Don't Reboot Userspace After Jailbreak" is enabled.
- (void)showJailbreakDoneWithoutReboot
{
    [[DOUIManager sharedInstance] sendLog:DOLocalizedString(@"Log_Jailbreak_Done_NoReboot") debug:NO];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Jailbreak_Done_NoReboot_Title")
                                                                            message:DOLocalizedString(@"Jailbreak_Done_NoReboot_Message")
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self fadeToBlack:^{
            [[DOEnvironmentManager sharedManager] rebootUserspace];
        }];
    }];
    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:rebootAction];
    [alertController addAction:laterAction];
    alertController.preferredAction = rebootAction;
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)simulateJailbreak
{
    // Let's simulate a "jailbreak" using grand central dispatch

    DOUIManager *uiManager = [DOUIManager sharedInstance];

    static BOOL didFinish = NO; //not thread safe lol


    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [uiManager completeJailbreak];
        [uiManager sendLog:@"Rebooting Userspace" debug: NO];
        didFinish = YES;
        [self fadeToBlack: ^{

        }];
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.2];
        [uiManager sendLog:@"Launching kexploitd" debug: NO];
        [NSThread sleepForTimeInterval:0.5];
        [uiManager sendLog:@"Launching oobPCI" debug: NO];
        [NSThread sleepForTimeInterval:0.15];
        [uiManager sendLog:@"Gaining r/w" debug: NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:@"Patchfinding" debug: NO];
        NSArray *types = @[@"AMFI", @"PAC", @"KTRR", @"KPP", @"PPL", @"KPF", @"APRR", @"AMCC", @"PAN", @"PXN", @"ASLR", @"OPA"]; //Ever heard of the legendary opa bypass
        while (true)
        {
            [NSThread sleepForTimeInterval:0.6 * rand() / RAND_MAX];
            if (didFinish) break;
            NSString *type = types[arc4random_uniform((uint32_t)types.count)];
            [uiManager sendLog:[NSString stringWithFormat:@"Bypassing %@", type] debug: NO];
        }
    });
}

- (void)fadeToBlack:(void (^)(void))completion
{
    static bool didFade = false;
    if (didFade)
        return;
    didFade = true;
    UIView *mainView = self.parentViewController.view;
    float deviceCornerRadius = [[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"] floatValue];

    mainView.layer.cornerRadius = deviceCornerRadius;
    mainView.layer.cornerCurve = kCACornerCurveContinuous;
    mainView.layer.masksToBounds = YES;

    self.hideStatusBar = YES;

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        mainView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        mainView.alpha = 0.0;
    } completion:^(BOOL success) {
        completion();
    }];
}

#pragma mark - DOActionMenuDelegate (kept for protocol conformance)

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"settings"] || [action.identifier isEqualToString:@"credits"]) return YES;
    return NO;
}

- (BOOL)actionMenuActionIsEnabled:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"respring"] || [action.identifier isEqualToString:@"reboot-userspace"]) {
        return [[DOEnvironmentManager sharedManager] isJailbroken];
    }
    return YES;
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden
{
    return self.hideStatusBar;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return self.hideHomeIndicator;
}

- (void)setHideStatusBar:(BOOL)hideStatusBar
{
    _hideStatusBar = hideStatusBar;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)setHideHomeIndicator:(BOOL)hideHomeIndicator
{
    _hideHomeIndicator = hideHomeIndicator;
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

@end
