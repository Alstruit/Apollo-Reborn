#import "ApolloManualSignInViewController.h"
#import "ApolloCommon.h"

// Raw userscript URL. Opening a *.user.js link in a Gecko browser triggers
// Tampermonkey/Violentmonkey's one-tap install prompt — far better UX than
// pasting raw script text into the editor — so we always hand over the link.
static NSString *const kApolloUserscriptURL =
    @"https://raw.githubusercontent.com/Apollo-Reborn/Apollo-Reborn/refs/heads/main/userscript/apollo-oauth-helper.user.js";

// Extracts a query OR fragment parameter from a URL string (defined below).
static NSString *ARExtractParam(NSString *urlString, NSString *name);

@interface ApolloManualSignInViewController ()
@property (nonatomic, copy) NSURL *authURL;
@property (nonatomic, copy) NSString *callbackScheme;
@property (nonatomic, copy) void (^onComplete)(NSURL *callbackURL);
@property (nonatomic, strong) UITextView *codeTextView;
@end

@implementation ApolloManualSignInViewController

- (instancetype)initWithAuthURL:(NSURL *)authURL
                 callbackScheme:(NSString *)scheme
                     onComplete:(void (^)(NSURL *callbackURL))onComplete {
    self = [super init];
    if (self) {
        _authURL = [authURL copy];
        _callbackScheme = [scheme copy];
        _onComplete = [onComplete copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Manual Sign-In";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20],
    ]];

    [stack addArrangedSubview:[self _headingLabel:@"Sign in with an external browser"]];
    [stack addArrangedSubview:[self _bodyLabel:
        @"Use this if the Reddit login page won't load in the in-app browser "
        @"(common on iOS 15.3.1 and earlier). You'll sign in using a Gecko-based "
        @"browser such as Reynard (v0.3.0 or later) with the helper userscript, "
        @"then paste the authorization code back here."]];

    [stack addArrangedSubview:[self _bodyLabel:
        @"1.  In Reynard, install the Tampermonkey add-on.\n"
        @"2.  Tap “Copy Userscript Link”, paste it into Reynard's address bar, "
        @"and tap Install when Tampermonkey prompts you.\n"
        @"3.  Tap “Copy Sign-In URL”, open it in Reynard, and sign in to Reddit.\n"
        @"4.  When Reddit asks to connect your account, tap “Accept.“\n"
        @"5.  A popup will appear with your authorization code. Copy it, return here, "
        @"paste it below, and tap “Complete Sign-In”."]];

    [stack addArrangedSubview:[self _button:@"Copy Userscript Link" filled:NO action:@selector(_copyUserscriptLink:)]];
    [stack addArrangedSubview:[self _button:@"Copy Sign-In URL" filled:NO action:@selector(_copyAuthURL:)]];

    [stack addArrangedSubview:[self _spacer:6]];
    [stack addArrangedSubview:[self _headingLabel:@"Authorization code"]];

    UITextView *tv = [UITextView new];
    tv.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    tv.backgroundColor = [UIColor secondarySystemBackgroundColor];
    tv.textColor = [UIColor labelColor];
    tv.layer.cornerRadius = 10;
    tv.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tv.autocorrectionType = UITextAutocorrectionTypeNo;
    tv.spellCheckingType = UITextSpellCheckingTypeNo;
    tv.scrollEnabled = NO;
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [tv.heightAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    self.codeTextView = tv;
    [stack addArrangedSubview:tv];

    [stack addArrangedSubview:[self _button:@"Paste from Clipboard" filled:NO action:@selector(_pasteFromClipboard:)]];
    [stack addArrangedSubview:[self _spacer:6]];
    [stack addArrangedSubview:[self _button:@"Complete Sign-In" filled:YES action:@selector(_completeTapped:)]];
}

#pragma mark - Actions

- (void)_copyUserscriptLink:(UIButton *)sender {
    [UIPasteboard generalPasteboard].string = kApolloUserscriptURL;
    [self _flashButton:sender title:@"Copied!"];
}

- (void)_copyAuthURL:(UIButton *)sender {
    NSString *urlString = self.authURL.absoluteString;
    if (urlString.length) {
        [UIPasteboard generalPasteboard].string = urlString;
        [self _flashButton:sender title:@"Copied!"];
    }
}

- (void)_pasteFromClipboard:(UIButton *)sender {
    NSString *clip = [UIPasteboard generalPasteboard].string;
    if (clip.length) {
        self.codeTextView.text = clip;
    } else {
        [self _flashButton:sender title:@"Clipboard empty"];
    }
}

- (void)_completeTapped:(UIButton *)sender {
    NSURL *callback = [self _buildCallbackURLFromText:self.codeTextView.text];
    if (!callback) {
        [self _alert:@"No code entered"
             message:@"Paste the authorization code (or the full callback URL) "
                     @"shown by the helper, then try again."];
        return;
    }
    ApolloLog(@"[ManualSignIn] completing with callback: %@", callback);
    if (self.onComplete) self.onComplete(callback);
}

#pragma mark - Callback synthesis

// Accepts either the raw authorization code or a full callback URL, and rebuilds
// the redirect Reddit would have produced: <redirect_uri>?state=<state>&code=<code>.
- (NSURL *)_buildCallbackURLFromText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;

    NSString *code = nil;
    NSString *state = nil;

    if ([trimmed containsString:@"code="]) {
        code  = ARExtractParam(trimmed, @"code");
        state = ARExtractParam(trimmed, @"state");
    }
    if (code.length == 0) {
        code = trimmed; // treat the whole paste as the bare code
    }

    // Pull redirect_uri (and state, if not already found) from the auth URL.
    NSString *redirectURI = nil;
    NSURLComponents *authComponents =
        [NSURLComponents componentsWithURL:self.authURL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in authComponents.queryItems) {
        if ([item.name isEqualToString:@"redirect_uri"]) {
            redirectURI = item.value;
        } else if ([item.name isEqualToString:@"state"] && state.length == 0) {
            state = item.value;
        }
    }
    if (redirectURI.length == 0) {
        redirectURI = [NSString stringWithFormat:@"%@://", self.callbackScheme ?: @"apollo"];
    }

    NSURLComponents *cb = [NSURLComponents componentsWithString:redirectURI];
    if (cb) {
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        if (state.length) [items addObject:[NSURLQueryItem queryItemWithName:@"state" value:state]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"code" value:code]];
        cb.queryItems = items;
        if (cb.URL) return cb.URL;
    }

    // Fallback: assemble the string by hand (redirect_uri may be just "scheme://").
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSMutableString *str = [NSMutableString stringWithString:redirectURI];
    [str appendString:[redirectURI containsString:@"?"] ? @"&" : @"?"];
    if (state.length) {
        [str appendFormat:@"state=%@&",
            [state stringByAddingPercentEncodingWithAllowedCharacters:allowed]];
    }
    [str appendFormat:@"code=%@",
        [code stringByAddingPercentEncodingWithAllowedCharacters:allowed]];
    return [NSURL URLWithString:str];
}

// Extracts a query OR fragment parameter from a URL string.
static NSString *ARExtractParam(NSString *urlString, NSString *name) {
    NSURLComponents *c = [NSURLComponents componentsWithString:urlString];
    if (!c) return nil;
    for (NSURLQueryItem *item in c.queryItems) {
        if ([item.name isEqualToString:name]) return item.value;
    }
    if (c.fragment.length) {
        NSURLComponents *fc = [NSURLComponents new];
        fc.query = c.fragment; // reuse query parser on the fragment
        for (NSURLQueryItem *item in fc.queryItems) {
            if ([item.name isEqualToString:name]) return item.value;
        }
    }
    return nil;
}

#pragma mark - UI helpers

- (UILabel *)_headingLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.numberOfLines = 0;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    l.textColor = [UIColor labelColor];
    return l;
}

- (UILabel *)_bodyLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.numberOfLines = 0;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    l.textColor = [UIColor secondaryLabelColor];
    return l;
}

- (UIView *)_spacer:(CGFloat)height {
    UIView *v = [UIView new];
    [v.heightAnchor constraintEqualToConstant:height].active = YES;
    return v;
}

- (UIButton *)_button:(NSString *)title filled:(BOOL)filled action:(SEL)action {
    UIButtonConfiguration *cfg = filled
        ? [UIButtonConfiguration filledButtonConfiguration]
        : [UIButtonConfiguration tintedButtonConfiguration];
    cfg.title = title;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(12, 16, 12, 16);

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.configuration = cfg;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)_flashButton:(UIButton *)button title:(NSString *)title {
    UIButtonConfiguration *cfg = button.configuration;
    NSString *original = cfg.title;
    cfg.title = title;
    button.configuration = cfg;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIButtonConfiguration *c = button.configuration;
        c.title = original;
        button.configuration = c;
    });
}

- (void)_alert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
