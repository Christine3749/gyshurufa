#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import <fcntl.h>
#import <stdio.h>
#import <unistd.h>

@interface GYInputController : IMKInputController
@end

static void Trace(const char *event) {
  static int file = -1;
  static int wroteRuntimeMetadata = 0;
  if (file < 0) file = open("/tmp/GYInput-core.trace", O_WRONLY | O_APPEND | O_CREAT, 0600);
  if (file >= 0) {
    if (!wroteRuntimeMetadata) {
      wroteRuntimeMetadata = 1;
      NSBundle *bundle = NSBundle.mainBundle;
      NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
      NSString *identifier = bundle.bundleIdentifier ?: @"unknown";
      dprintf(file, "pid=%d build=%s route=inputText:key:modifiers:client: bundle=%s\n",
              getpid(), build.UTF8String, identifier.UTF8String);
    }
    dprintf(file, "%s\n", event);
  }
}

static NSString *CommitForCode(NSString *code) {
  if ([code isEqualToString:@"nihao"]) return @"你好";
  return code;
}

@implementation GYInputController {
  __weak id _activeClient;
  NSMutableString *_composition;
}

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)client {
  self = [super initWithServer:server delegate:delegate client:client];
  if (self != nil) {
    _activeClient = client;
    _composition = [NSMutableString string];
    Trace("controller-init");
  }
  return self;
}

- (void)activateServer:(id)sender {
  _activeClient = sender;
  Trace("controller-activate");
}

- (void)deactivateServer:(id)sender {
  (void)sender;
  Trace("controller-deactivate");
  [self clearComposition];
  _activeClient = nil;
}

- (id)currentClient {
  return _activeClient ?: self.client;
}

- (void)showComposition {
  id client = [self currentClient];
  if (client == nil || _composition.length == 0) return;
  NSAttributedString *text = [[NSAttributedString alloc] initWithString:_composition];
  [client setMarkedText:text
          selectionRange:NSMakeRange(_composition.length, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)clearComposition {
  [_composition setString:@""];
  id client = [self currentClient];
  if ([client respondsToSelector:@selector(unmarkText)]) [client unmarkText];
}

- (void)commitComposition {
  if (_composition.length == 0) return;
  id client = [self currentClient];
  if (client != nil) {
    [client insertText:CommitForCode(_composition) replacementRange:NSMakeRange(NSNotFound, 0)];
  }
  [self clearComposition];
}

- (BOOL)inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)modifiers client:(id)client {
  _activeClient = client;
  Trace("text-event");
  NSEventModifierFlags blocked = NSEventModifierFlagCommand | NSEventModifierFlagControl |
      NSEventModifierFlagOption | NSEventModifierFlagFunction;
  if ((modifiers & blocked) != 0) return NO;

  if (keyCode == kVK_Escape && _composition.length != 0) {
    [self clearComposition];
    return YES;
  }
  if (keyCode == kVK_Delete) {
    if (_composition.length == 0) return NO;
    [_composition deleteCharactersInRange:NSMakeRange(_composition.length - 1, 1)];
    if (_composition.length == 0) [self clearComposition];
    else [self showComposition];
    return YES;
  }
  if (keyCode == kVK_Space && _composition.length != 0) {
    [self commitComposition];
    return YES;
  }

  NSString *characters = string;
  if (characters.length == 1 && [characters rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound) {
    [_composition appendString:characters];
    [self showComposition];
    return YES;
  }

  if (_composition.length != 0) [self commitComposition];
  return NO;
}

- (void)inputControllerWillClose {
  [self clearComposition];
  [super inputControllerWillClose];
}

@end
