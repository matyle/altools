// Loaded into /usr/bin/perl, which macOS lets talk to the private MediaRemote framework.
// Streams the system's Now Playing state as JSON lines on stdout and reads commands
// ("toggle", "next", "previous", "seek <seconds>") from stdin.
#import <AppKit/AppKit.h>
#import <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

static GetInfoFn getInfo;
static GetPIDFn getPID;
static GetPlayingFn getPlaying;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;
static NSString *lastArtworkKey = @"";

static void emit(void) {
  dispatch_queue_t q = dispatch_get_main_queue();
  getInfo(q, ^(CFDictionaryRef raw) {
    NSDictionary *info = (__bridge NSDictionary *)raw;
    getPlaying(q, ^(Boolean playing) {
      getPID(q, ^(int pid) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        out[@"playing"] = @(playing);
        NSString *bundle = pid > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier : nil;
        if (bundle) out[@"bundle"] = bundle;
        NSDictionary *keys = @{@"title": @"kMRMediaRemoteNowPlayingInfoTitle",
                               @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
                               @"album": @"kMRMediaRemoteNowPlayingInfoAlbum",
                               @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
                               @"elapsed": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
                               @"rate": @"kMRMediaRemoteNowPlayingInfoPlaybackRate"};
        for (NSString *k in keys) {
          id v = info[keys[k]];
          if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class]) out[k] = v;
        }
        NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([stamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @(stamp.timeIntervalSince1970);
        NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        NSString *artKey = [NSString stringWithFormat:@"%@|%@|%lu", out[@"title"], out[@"artist"], (unsigned long)art.length];
        if ([art isKindOfClass:NSData.class] && art.length > 0 && ![artKey isEqualToString:lastArtworkKey]) {
          out[@"artwork"] = [art base64EncodedStringWithOptions:0];
        }
        if (art.length > 0) lastArtworkKey = artKey;
        NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
        if (!json) return;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        fflush(stdout);
      });
    });
  });
}

static void handle(NSString *line) {
  if ([line isEqualToString:@"toggle"]) sendCommand(2, NULL);
  else if ([line isEqualToString:@"next"]) sendCommand(4, NULL);
  else if ([line isEqualToString:@"previous"]) sendCommand(5, NULL);
  else if ([line hasPrefix:@"seek "]) setElapsed([[line substringFromIndex:5] doubleValue]);
  else if ([line isEqualToString:@"refresh"]) emit();
}

// Installed as a perl XSUB; perl's arguments are ignored. Never returns.
void altools_media_stream(void *perl, void *cv) {
  void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
  if (!mr) { fprintf(stderr, "MediaRemote unavailable\n"); exit(2); }
  getInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
  getPID = (GetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
  getPlaying = (GetPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
  sendCommand = (SendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
  setElapsed = (SetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
  RegisterFn reg = (RegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
  if (!getInfo || !getPID || !getPlaying || !sendCommand || !setElapsed || !reg) { fprintf(stderr, "MediaRemote symbols missing\n"); exit(2); }

  reg(dispatch_get_main_queue());
  for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { emit(); }];
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    char buf[256];
    while (fgets(buf, sizeof buf, stdin)) {
      NSString *line = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      dispatch_async(dispatch_get_main_queue(), ^{ handle(line); });
    }
    exit(0); // the app closed our stdin: it quit or restarted the bridge
  });
  emit();
  [NSRunLoop.mainRunLoop run];
}
