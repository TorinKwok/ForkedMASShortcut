#import "MASShortcut+Monitoring.h"

NSMutableDictionary* MASRegisteredHotKeys();
BOOL InstallCommonEventHandler();
BOOL InstallHotkeyWithShortcut( MASShortcut* _Shortcut, UInt32* _OutCarbonHotKeyID, EventHotKeyRef* _OutCarbonHotKey );
void UninstallEventHandler();

#pragma mark MASShortcutHotKey class interface
@interface MASShortcutHotKey : NSObject
    {
    MASShortcut* _shortcut;
    void ( ^_handler )();
    EventHotKeyRef _carbonHotKey;
    UInt32 _carbonHotKeyID;
    }

@property ( nonatomic, readonly, retain ) MASShortcut* shortcut;
@property ( nonatomic, readonly, copy ) void ( ^handler )();
@property ( nonatomic, readonly ) EventHotKeyRef carbonHotKey;
@property ( nonatomic, readonly ) UInt32 carbonHotKeyID;

- ( id ) initWithShortcut: ( MASShortcut* )_Shortcut handler: ( void (^)() )_Handler;
- ( void ) uninstallExistingHotKey;

@end // MASShortcutHotKey class interface

#pragma mark MASShortcut + MASShorcutMonitoring
@implementation MASShortcut ( MASShorcutMonitoring )

+ ( id ) addGlobalHotkeyMonitorWithShortcut: ( MASShortcut* )_Shortcut
                                    handler: ( void (^)() )_Handler
    {
    NSString* monitor = [ NSString stringWithFormat: @"%@", _Shortcut.description ];
    if ( [ MASRegisteredHotKeys() objectForKey: monitor ] )
        return nil;

    MASShortcutHotKey* hotKey = [ [ [ MASShortcutHotKey alloc ] initWithShortcut: _Shortcut
                                                                         handler: _Handler ] autorelease ];
    if ( hotKey == nil )
        return nil;

    [ MASRegisteredHotKeys() setObject: hotKey forKey: monitor ];
    
    return monitor;
    }

+ ( void ) removeGlobalHotkeyMonitor: ( id )_Monitor;
{
    if (_Monitor == nil) return;
    NSMutableDictionary *registeredHotKeys = MASRegisteredHotKeys();
    MASShortcutHotKey *hotKey = [registeredHotKeys objectForKey: _Monitor];
    if (hotKey)
    {
        [hotKey uninstallExistingHotKey];
    }
    [registeredHotKeys removeObjectForKey:_Monitor];

    if (registeredHotKeys.count == 0) {
        UninstallEventHandler();
    }
}

@end // MASShortcut + MASShorcutMonitoring

#pragma mark MASShortcutHotKey class implementation
@implementation MASShortcutHotKey

@synthesize carbonHotKeyID = _carbonHotKeyID;
@synthesize handler = _handler;
@synthesize shortcut = _shortcut;
@synthesize carbonHotKey = _carbonHotKey;

#pragma mark Initializers & deallocator
- ( id ) initWithShortcut: ( MASShortcut* )_Shortcut handler: ( void (^)() )_Handler;
    {
    if ( self = [ super init ] )
        {
        _shortcut = [_Shortcut retain];
        _handler = [_Handler copy];

        if (!InstallHotkeyWithShortcut(_Shortcut, &_carbonHotKeyID, &_carbonHotKey))
            {
            [self release];
            self = nil;
            }
        }

    return self;
    }

- ( void ) dealloc
    {
    [ _shortcut release ];
    [ self uninstallExistingHotKey ];
    [ super dealloc ];
    }

#pragma mark -
- (void)uninstallExistingHotKey
{
    if (_carbonHotKey) {
        UnregisterEventHotKey(_carbonHotKey);
        _carbonHotKey = NULL;
    }
}

@end // MASShortcutHotKey class implementation

#pragma mark Carbon magic
NSMutableDictionary* MASRegisteredHotKeys()
    {
    NSMutableDictionary static* shared = nil;
    dispatch_once_t static onceToken;

    dispatch_once( &onceToken,
        ^{ shared = [ [ NSMutableDictionary dictionary ] retain ]; } );

    return shared;
    }

FourCharCode const kMASShortcutSignature = 'MASS';

BOOL InstallHotkeyWithShortcut(MASShortcut *shortcut, UInt32 *outCarbonHotKeyID, EventHotKeyRef *outCarbonHotKey)
{
    if ((shortcut == nil) || !InstallCommonEventHandler()) return NO;

    static UInt32 sCarbonHotKeyID = 0;
	EventHotKeyID hotKeyID = { .signature = kMASShortcutSignature, .id = ++ sCarbonHotKeyID };
    EventHotKeyRef carbonHotKey = NULL;
    if (RegisterEventHotKey(shortcut.carbonKeyCode, shortcut.carbonFlags, hotKeyID, GetEventDispatcherTarget(), kEventHotKeyExclusive, &carbonHotKey) != noErr) {
        return NO;
    }

    if (outCarbonHotKeyID) *outCarbonHotKeyID = hotKeyID.id;
    if (outCarbonHotKey) *outCarbonHotKey = carbonHotKey;
    return YES;
}

static OSStatus CarbonCallback(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData)
{
	if (GetEventClass(inEvent) != kEventClassKeyboard) return noErr;

	EventHotKeyID hotKeyID;
	OSStatus status = GetEventParameter(inEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
	if (status != noErr) return status;

	if (hotKeyID.signature != kMASShortcutSignature) return noErr;

    [MASRegisteredHotKeys() enumerateKeysAndObjectsUsingBlock:^(id key, MASShortcutHotKey *hotKey, BOOL *stop) {
        if (hotKeyID.id == hotKey.carbonHotKeyID) {
            if (hotKey.handler) {
                hotKey.handler();
            }
            *stop = YES;
        }
    }];

	return noErr;
}

static EventHandlerRef sEventHandler = NULL;

BOOL InstallCommonEventHandler()
{
    if (sEventHandler == NULL) {
        EventTypeSpec hotKeyPressedSpec = { .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed };
        OSStatus status = InstallEventHandler(GetEventDispatcherTarget(), CarbonCallback, 1, &hotKeyPressedSpec, NULL, &sEventHandler);
        if (status != noErr) {
            sEventHandler = NULL;
            return NO;
        }
    }
    return YES;
}

void UninstallEventHandler()
{
    if (sEventHandler) {
        RemoveEventHandler(sEventHandler);
        sEventHandler = NULL;
    }
}
