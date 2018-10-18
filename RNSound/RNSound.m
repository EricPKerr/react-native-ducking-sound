#import "RNSound.h"

#if __has_include("RCTUtils.h")
    #import "RCTUtils.h"
#else
    #import <React/RCTUtils.h>
#endif

@implementation RNSound {
  NSMutableDictionary* _playerPool;
  NSMutableDictionary* _callbackPool;
}

@synthesize _key = _key;

- (void)audioSessionChangeObserver:(NSNotification *)notification{
    NSDictionary* userInfo = notification.userInfo;
    AVAudioSessionRouteChangeReason audioSessionRouteChangeReason = [userInfo[@"AVAudioSessionRouteChangeReasonKey"] longValue];
    AVAudioSessionInterruptionType audioSessionInterruptionType   = [userInfo[@"AVAudioSessionInterruptionTypeKey"] longValue];
    AVAudioPlayer* player = [self playerForKey:self._key];
    if (audioSessionRouteChangeReason == AVAudioSessionRouteChangeReasonNewDeviceAvailable){
        if (player) {
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            [player play];
        }
    }
    if (audioSessionInterruptionType == AVAudioSessionInterruptionTypeEnded){
        if (player && player.isPlaying) {
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            [player play];
        }
    }
    if (audioSessionRouteChangeReason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable){
        if (player) {
            [[AVAudioSession sharedInstance] setActive:NO error:nil];
            [player pause];
        }
    }
    if (audioSessionInterruptionType == AVAudioSessionInterruptionTypeBegan){
        if (player) {
            [[AVAudioSession sharedInstance] setActive:NO error:nil];
            [player pause];
        }
    }
}

-(NSMutableDictionary*) playerPool {
  if (!_playerPool) {
    _playerPool = [NSMutableDictionary new];
  }
  return _playerPool;
}

-(NSMutableDictionary*) callbackPool {
  if (!_callbackPool) {
    _callbackPool = [NSMutableDictionary new];
  }
  return _callbackPool;
}

-(AVAudioPlayer*) playerForKey:(nonnull NSNumber*)key {
  return [[self playerPool] objectForKey:key];
}

-(NSNumber*) keyForPlayer:(nonnull AVAudioPlayer*)player {
  return [[[self playerPool] allKeysForObject:player] firstObject];
}

-(RCTResponseSenderBlock) callbackForKey:(nonnull NSNumber*)key {
  return [[self callbackPool] objectForKey:key];
}

-(NSString *) getDirectory:(int)directory {
  return [NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES) firstObject];
}

-(void) audioPlayerDidFinishPlaying:(AVAudioPlayer*)player
                       successfully:(BOOL)flag {
  NSNumber* key = [self keyForPlayer:player];
  if (key == nil) return;

  @synchronized(key) {
    [self setOnPlay:NO forPlayerKey:key];
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    RCTResponseSenderBlock callback = [self callbackForKey:key];
    if (callback) {
      callback(@[@(flag)]);
      [[self callbackPool] removeObjectForKey:key];
    }
  }
}

RCT_EXPORT_MODULE();

-(NSArray<NSString *> *)supportedEvents
  {
    return @[@"onPlayChange"];
  }

-(NSDictionary *)constantsToExport {
  return @{@"IsAndroid": [NSNumber numberWithBool:NO],
           @"MainBundlePath": [[NSBundle mainBundle] bundlePath],
           @"NSDocumentDirectory": [self getDirectory:NSDocumentDirectory],
           @"NSLibraryDirectory": [self getDirectory:NSLibraryDirectory],
           @"NSCachesDirectory": [self getDirectory:NSCachesDirectory],
           };
}

RCT_EXPORT_METHOD(setActive:(BOOL)active) {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setActive: active error: nil];
}

RCT_EXPORT_METHOD(prepare:(NSString*)fileName
                  withKey:(nonnull NSNumber*)key
                  withOptions:(NSDictionary*)options
                  withCallback:(RCTResponseSenderBlock)callback) {
  NSError* error;
  NSURL* fileNameUrl;
  AVAudioPlayer* player;

  if ([fileName hasPrefix:@"http"]) {
    fileNameUrl = [NSURL URLWithString:fileName];
    NSData* data = [NSData dataWithContentsOfURL:fileNameUrl];
    player = [[AVAudioPlayer alloc] initWithData:data error:&error];
  }
  else if ([fileName hasPrefix:@"ipod-library://"]) {
    fileNameUrl = [NSURL URLWithString:fileName];
    player = [[AVAudioPlayer alloc] initWithContentsOfURL:fileNameUrl error:&error];
  }
  else {
    fileNameUrl = [NSURL URLWithString: fileName];
    player = [[AVAudioPlayer alloc]
              initWithContentsOfURL:fileNameUrl
              error:&error];
  }

  if (player) {
    player.delegate = self;
    player.enableRate = YES;
    [player prepareToPlay];
    [[self playerPool] setObject:player forKey:key];
    callback(@[[NSNull null], @{@"duration": @(player.duration),
                                @"numberOfChannels": @(player.numberOfChannels)}]);
  } else {
    callback(@[RCTJSErrorFromNSError(error)]);
  }
}

RCT_EXPORT_METHOD(play:(nonnull NSNumber*)key withCallback:(RCTResponseSenderBlock)callback) {
  AVAudioSession *session = [AVAudioSession sharedInstance];

  [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionDuckOthers
                       error:nil];

  [session setActive:YES error:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionChangeObserver:) name:AVAudioSessionRouteChangeNotification object:nil];
  self._key = key;
  AVAudioPlayer* player = [self playerForKey:key];
  if (player) {
    [[self callbackPool] setObject:[callback copy] forKey:key];
    [player play];
    [self setOnPlay:YES forPlayerKey:key];
  }
}

RCT_EXPORT_METHOD(pause:(nonnull NSNumber*)key withCallback:(RCTResponseSenderBlock)callback) {
  AVAudioPlayer* player = [self playerForKey:key];
  if (player) {
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    [player pause];
    callback(@[]);
  }
}

RCT_EXPORT_METHOD(stop:(nonnull NSNumber*)key withCallback:(RCTResponseSenderBlock)callback) {
  AVAudioPlayer* player = [self playerForKey:key];
  if (player) {
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    [player stop];
    player.currentTime = 0;
    callback(@[]);
  }
}

RCT_EXPORT_METHOD(release:(nonnull NSNumber*)key) {
  AVAudioPlayer* player = [self playerForKey:key];
  if (player) {
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    [player stop];
    [[self callbackPool] removeObjectForKey:player];
    [[self playerPool] removeObjectForKey:key];
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
  }
}

RCT_EXPORT_METHOD(setVolume:(nonnull NSNumber*)key withValue:(nonnull NSNumber*)value) {
  AVAudioPlayer* player = [self playerForKey:key];
  if (player) {
    player.volume = [value floatValue];
  }
}

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}
- (void)setOnPlay:(BOOL)isPlaying forPlayerKey:(nonnull NSNumber*)playerKey {
  [self sendEventWithName:@"onPlayChange" body:@{@"isPlaying": isPlaying ? @YES : @NO, @"playerKey": playerKey}];
}
@end
