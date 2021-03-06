//
//  BTSBViewController.m
//  BTScoreboard
//
// The MIT License (MIT)
//
// Copyright (c) 2013 Thomas Propst
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so,subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS ORCOPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHERIN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR INCONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "BTSBViewController.h"

@interface BTSBViewController ()

- (IBAction)homeScoreChange:(id)sender;
- (IBAction)visitorSccoreChange:(id)sender;
- (IBAction)timeStartStop:(id)sender;
- (IBAction)resetClick:(id)sender;
@property (weak, nonatomic) IBOutlet UIButton *homeScore;
@property int homeScoreValue;
@property (weak, nonatomic) IBOutlet UIButton *visitorScore;
@property int visitorScoreValue;
@property (weak, nonatomic) IBOutlet UIButton *timeDisplay;
@property int gameTimeSeconds;

@end

@implementation BTSBViewController

// Core Bluetooth Central Manager instance
CBCentralManager *cbCentralManager;
CBPeripheral *cbPeripheral;
CBUUID *simpleKeyServiceUuid;
CBUUID *simpleKeyCharUuid;
bool connected = false;
const int scanTimeout = 180; // seconds - default timeout for TI devices
int scanTime;

double lastKeyEventTime;
const double tapTime = 0.500; // seconds between key events
bool clickStarted;
int lastKeyEventCode;
double lastKeyClickTime;
int lastKeyClickCode;

// Right / left keys on the sensor tag are switched compared to the fob.
// Need to keep track of which type of device is connected.
enum deviceType
{
    none,
    tiSensorTag,
    tiKeyFob
} discoveredDevice;

NSTimer *gameTimer;

int gameLength;

CFURLRef buzzerFileUrl;
SystemSoundID buzzerSoundId;
CFURLRef countdownFileUrl;
SystemSoundID countdownSoundId;
CFURLRef startFileUrl;
SystemSoundID startSoundId;
CFURLRef stopFileUrl;
SystemSoundID stopSoundId;
CFURLRef scoreFileUrl;
SystemSoundID scoreSoundId;

const int gameLengthOptions[] = {1,2,3,4,5,6,7,8,9,10,15,20,30,45,60,90};

CALayer *connectButtonLayer;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    connectButtonLayer = [_connectButton layer];
    [connectButtonLayer setMasksToBounds:YES];
    [connectButtonLayer setCornerRadius:15.0f];
    [connectButtonLayer setBorderColor:[UIColor blueColor].CGColor];
    [connectButtonLayer setBorderWidth:3.0f];
    [connectButtonLayer setBackgroundColor:nil];
    
    // Allocate the CB central manager as a delegate
    cbCentralManager = [[CBCentralManager alloc] initWithDelegate:self
                                                            queue:nil
                                                          options:nil];
    
    // Service and characteristic UUID's defined by TI BLE devices
    simpleKeyServiceUuid  = [CBUUID
                    UUIDWithString:@"0000ffe0-0000-1000-8000-00805f9b34fb"];
    simpleKeyCharUuid = [CBUUID
                    UUIDWithString:@"0000ffe1-0000-1000-8000-00805f9b34fb"];
    
    // Initialize the game parameters
    self.homeScoreValue = 0;
    self.visitorScoreValue = 0;
    // Default to 10 minute game
    gameLength = gameLengthOptions[9] * 60;
    self.gameTimeSeconds = gameLength;
    [_gameLengthPicker selectRow:9 inComponent:0 animated:NO];
    [self updateBoard];
    
    // Initialize timers and codes used for key events
    lastKeyEventTime = 0;
    lastKeyClickTime = 0;
    clickStarted = false;
    lastKeyEventCode = 0;
    lastKeyClickCode = 0;
    
    discoveredDevice = none;
    
    buzzerFileUrl = (__bridge CFURLRef) [[NSBundle mainBundle]
                                         URLForResource: @"buzzer"
                                         withExtension: @"mp3"];
    AudioServicesCreateSystemSoundID (buzzerFileUrl, &buzzerSoundId);
    countdownFileUrl = (__bridge CFURLRef) [[NSBundle mainBundle]
                                            URLForResource: @"countdown"
                                            withExtension: @"m4a"];
    AudioServicesCreateSystemSoundID (countdownFileUrl, &countdownSoundId);
    scoreFileUrl = (__bridge CFURLRef) [[NSBundle mainBundle]
                                         URLForResource: @"fanfare"
                                         withExtension: @"m4a"];
    AudioServicesCreateSystemSoundID (scoreFileUrl, &scoreSoundId);
    startFileUrl = (__bridge CFURLRef) [[NSBundle mainBundle]
                                        URLForResource: @"start"
                                        withExtension: @"m4a"];
    AudioServicesCreateSystemSoundID (startFileUrl, &startSoundId);
    stopFileUrl = (__bridge CFURLRef) [[NSBundle mainBundle]
                                        URLForResource: @"stop"
                                        withExtension: @"m4a"];
    AudioServicesCreateSystemSoundID (stopFileUrl, &stopSoundId);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) dealloc
{
    AudioServicesDisposeSystemSoundID(buzzerSoundId);
    CFRelease(buzzerFileUrl);
    AudioServicesDisposeSystemSoundID(countdownSoundId);
    CFRelease(countdownFileUrl);
    AudioServicesDisposeSystemSoundID(scoreSoundId);
    CFRelease(scoreFileUrl);
    AudioServicesDisposeSystemSoundID(stopSoundId);
    CFRelease(stopFileUrl);
    AudioServicesDisposeSystemSoundID(startSoundId);
    CFRelease(startFileUrl);
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView
    numberOfRowsInComponent:(NSInteger)component
{
    return sizeof(gameLengthOptions)/sizeof(gameLengthOptions[0]);
}

- (NSString *)pickerView:(UIPickerView *)pickerView
             titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return [NSString stringWithFormat:@"%d",gameLengthOptions[row]];
}

- (void)pickerView:(UIPickerView *)pickerView
      didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    gameLength = gameLengthOptions[row] * 60;

}


- (void) updateBoard
{
    [self updateTimer];
    NSString *homeString = [NSString stringWithFormat:@"%02d",
                            self.homeScoreValue];
    [self.homeScore setTitle:homeString forState:UIControlStateNormal];
    NSString *visitorString = [NSString stringWithFormat:@"%02d",
                               self.visitorScoreValue];
    [self.visitorScore setTitle:visitorString forState:UIControlStateNormal];
    
}

- (void) updateTimer
{
    // The button title flashes when the title is changed.
    // Removing this annoyance when the timer updates.
    [UIView setAnimationsEnabled:NO];
    int mins = (int) (self.gameTimeSeconds / 60);
    int secs = self.gameTimeSeconds - (mins * 60);
    NSString *timeString = [NSString stringWithFormat:@"%02d:%02d", mins, secs];
    [self.timeDisplay setTitle:timeString forState:UIControlStateNormal];
    [UIView setAnimationsEnabled:YES];
}

- (void) tickTimer
{
    self.gameTimeSeconds--;
    [self updateTimer];
    if(self.gameTimeSeconds > 0)
    {
        return;
    }
    [self stopTimer];
    AudioServicesPlaySystemSound(buzzerSoundId);
}

// This method must be implemented for the CB central manager delegate
- (void) centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state == CBCentralManagerStatePoweredOn)
    {
        NSLog(@"BT powered on");
        [self startBleScan];
    } else
    {
        NSLog(@"BT is not on");
        [connectButtonLayer setBackgroundColor:[UIColor redColor].CGColor];
    }
}

- (void) startBleScan
{
    scanTime = scanTimeout;

    NSLog(@"Scanning for peripherals");

    // Begin scanning for TI keys
    // No services are specified because the TI keys don't advertise
    // services by default so I'm not specifying a service filter.
    [cbCentralManager scanForPeripheralsWithServices:nil options:nil];
    [connectButtonLayer setBackgroundColor:nil];
    [self tickScanner];

}

- (void) tickScanner
{
    NSLog(@"Scanning %d seconds", scanTime);
    if(![gameTimer isValid]) scanTime--;
    [UIView animateWithDuration:0.5
                          delay:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         [connectButtonLayer setBackgroundColor:
                          [UIColor blueColor].CGColor];
                     }
                     completion:^(BOOL finished){
                         [UIView animateWithDuration:0.5
                                               delay:0
                               options:UIViewAnimationOptionAllowUserInteraction
                                          animations:^{
                                              [connectButtonLayer
                                               setBackgroundColor:nil];
                                          }
                                          completion:^(BOOL finished){
                                              if((scanTime <= 0) &&
                                                 (!connected))
                                              {
                                                  NSLog(@"Scanner expired");
                                                  [self stopBleScan];
                                              }
                                              else if(!connected)
                                              {
                                                  [self tickScanner];
                                              }
                                              else
                                              {
                                                  [connectButtonLayer
                                                   setBackgroundColor:
                                                   [UIColor blueColor].CGColor];
                                              }
                                          }];
                     }];
}

- (void) stopBleScan
{
    NSLog(@"Stopping scan");
    [cbCentralManager stopScan];
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI
{
    // The name seems like the only way to filter these tags out of the box
    // without connecting to them.
    // Connecting to them may not be that bad and surely would be more reliable.
    if ([peripheral.name compare:@"TI BLE Sensor Tag"] == NSOrderedSame)
    {
        NSLog(@"Discovered TI Sensor Tag");
        discoveredDevice = tiSensorTag;
    }
    else if ([peripheral.name compare:@"TI BLE Keyfob"] == NSOrderedSame)
    {
        NSLog(@"Discovered TI Key Fob");
        discoveredDevice = tiKeyFob;
    }
    if(discoveredDevice != none)
    {
        cbPeripheral = peripheral;
        [self stopBleScan];
        NSLog(@"Stopped scanning for peripherals");
        [cbCentralManager connectPeripheral:peripheral options:nil];
    }
    else
    {
        NSLog(@"Discovered something other than a TI Tag");
        NSLog(@"%@", peripheral.name);
    }
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Connected to peripheral %@", peripheral.name);
    peripheral.delegate = self;
    [peripheral discoverServices:[NSArray
                                  arrayWithObject:simpleKeyServiceUuid]];
}

- (void)centralManager:(CBCentralManager *)central
    didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral disconnected");
    if(connected)
    {
        [connectButtonLayer setBackgroundColor:nil];
        discoveredDevice = none;
        connected = false;
        // If disconnected for some reason, try to reconnect once
        [self startBleScan];
    }
    //[self stopBleScan];
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
    NSLog(@"Peripheral connection failed");
}

- (void) peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error
{
    if (error == nil)
    {
        if(peripheral.services.count > 1)
        {
            NSLog(@"Warning: Found more than one simple key service");
        }
        for (CBService *service in peripheral.services) {
            NSLog(@"Discovered simple key service %@", service.description);
            [peripheral discoverCharacteristics:
             [NSArray arrayWithObject:simpleKeyCharUuid] forService:service];
            break;
        }
        return;
    }
    NSLog(@"No simple key service found");
}

- (void) peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
              error:(NSError *)error
{
    if(error == nil)
    {
        if(service.characteristics.count > 1)
        {
            NSLog(@"Warning: Found more than one simple key characteristic");
        }
        for (CBCharacteristic *characteristic in service.characteristics)
        {
            NSLog(@"Discovered characteristic %@", characteristic);
            NSLog(@"Subscribing for key notifications");
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            break;
        }
        return;
    }
    NSLog(@"No simple key characeristic found");
}

- (void) peripheral:(CBPeripheral *)peripheral
didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
              error:(NSError *)error
{
    if(error == nil)
    {
        NSLog(@"Notification subscription successful");
        connected = true;
        [connectButtonLayer setBackgroundColor:[UIColor blueColor].CGColor];
        return;
    }
    NSLog(@"Subscription failed: %@", [error localizedDescription]);
}

- (void) peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
              error:(NSError *)error
{
    double timeNow = CACurrentMediaTime();
    // The key value should be two bytes
    int keyValue = *(int *)([characteristic.value bytes]);
    // NSLog(@"Key value: %d", keyValue);
    
    // Is this a new key event or part of an in-process key event?
    double timeGap = timeNow - lastKeyEventTime;
    if((timeGap > tapTime) || (!clickStarted))
    {
        [self startNewClick:keyValue];
    } else
    {
        [self processClick:keyValue];
    }
    lastKeyEventTime = CACurrentMediaTime();
    
}

// The key events (key down and key up) are interpretted as:
// - left key click
// - right key click
// - multi key click (both keys together)
// A "click" is a key down / up within "tapTime".  Holding keys longer than
// tapTime negates the action (but can be used later for a "long click").

- (void) startNewClick:(int)keyValue
{
    switch (keyValue) {
        case 1:
        case 2:
        case 3:
            clickStarted = true;
            lastKeyEventCode = keyValue;
            break;
        case 0:
        default:
            [self clearClick];
    };
 
}

- (void) processClick:(int)keyValue
{
    double timeNow = CACurrentMediaTime();
    switch (keyValue) {
        case 0:
            clickStarted = false;
            lastKeyClickTime = timeNow;
            switch (lastKeyEventCode) {
                case 1:
                    lastKeyClickCode = 1;
                    NSLog(@"Left Click");
                    if(discoveredDevice == tiSensorTag)
                        [self visitorSccoreChange:NULL];
                    else [self homeScoreChange:NULL];
                    [self updateBoard];
                    break;
                case 2:
                    lastKeyClickCode = 2;
                    NSLog(@"Right Click");
                    if(discoveredDevice == tiSensorTag)
                        [self homeScoreChange:NULL];
                    else [self visitorSccoreChange:NULL];
                    [self updateBoard];
                    break;
                case 3:
                case 4:
                    lastKeyClickCode = 3;
                    NSLog(@"Multi Click");
                    [self timeStartStop:self];
                    break;
                default:
                    lastKeyClickCode = 0;
                    NSLog(@"Unknown Click");
            };
            break;
        case 1:
        case 2:
            if (lastKeyEventCode == 3) {
                lastKeyEventCode = 4;
            } else {
                [self clearClick];
            };
            break;
        case 3:
            lastKeyEventCode = 3;
            break;
        default:
            [self clearClick];
    };
}

- (void) clearClick
{
    clickStarted = false;
    lastKeyEventCode = 0;
    lastKeyClickCode = 0;
    lastKeyEventTime = 0;
    lastKeyClickTime = 0;

}

- (void) startTimer
{
    NSLog(@"Starting timer");
    
    // If this is the game start, play the countdown first
    if(gameLength == self.gameTimeSeconds)
    {
        // Subtract one second for the length of the start tone
        self.gameTimeSeconds--;
        AudioServicesAddSystemSoundCompletion(countdownSoundId, NULL, NULL,
                                              countdownSystemSoundCallback,
                                              (__bridge void *)(self));
        AudioServicesPlaySystemSound(countdownSoundId);
        return;
    }
    
    gameTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                 target:self
                                               selector:@selector(tickTimer)
                                               userInfo:nil repeats:YES];
    // Keep the screen on when the timer is running
    [[UIApplication sharedApplication] setIdleTimerDisabled: YES];
}

void countdownSystemSoundCallback(SystemSoundID ssID, void *mySelf)
{
    [(__bridge BTSBViewController *)mySelf updateTimer];
    [(__bridge BTSBViewController *)mySelf startTimer];
    AudioServicesRemoveSystemSoundCompletion(ssID);
}

- (void) stopTimer
{
    NSLog(@"Stopping timer");
    [gameTimer invalidate];
    // Allow screen to go idle when timer is stopped
    [[UIApplication sharedApplication] setIdleTimerDisabled: NO];
}

- (IBAction)homeScoreChange:(id)sender {
    self.homeScoreValue++;
    AudioServicesPlaySystemSound(scoreSoundId);
    [self updateBoard];
}

- (IBAction)visitorSccoreChange:(id)sender {
    NSLog(@"Visitor scores");
    self.visitorScoreValue++;
    AudioServicesPlaySystemSound(scoreSoundId);
    [self updateBoard];
}

- (IBAction)timeStartStop:(id)sender {
    if(gameTimer.isValid)
    {
        AudioServicesPlaySystemSound(stopSoundId);
        [self stopTimer];
        return;
    }
    if(gameLength != self.gameTimeSeconds)
        AudioServicesPlaySystemSound(startSoundId);
    [self startTimer];
}

- (IBAction)resetClick:(id)sender {
    [self stopTimer];
    self.homeScoreValue = 0;
    self.visitorScoreValue = 0;
    self.gameTimeSeconds = gameLength;
    [self updateBoard];
    [[UIApplication sharedApplication] setIdleTimerDisabled: NO];
}


- (IBAction)connectButtonPress:(id)sender {
    if(scanTime > 0)
    {
        scanTime = 0;
    }
    else if (!connected) [self startBleScan];
}
@end
