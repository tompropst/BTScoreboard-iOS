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

double lastKeyEventTime;
const double tapTime = 0.500; // seconds between key events
bool clickStarted;
int lastKeyEventCode;
double lastKeyClickTime;
int lastKeyClickCode;

NSTimer *gameTimer;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
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
    self.gameTimeSeconds = 15 * 60;
    self.homeScoreValue = 0;
    self.visitorScoreValue = 0;
    [self updateBoard];
    
    // Initialize timers and codes used for key events
    lastKeyEventTime = 0;
    lastKeyClickTime = 0;
    clickStarted = false;
    lastKeyEventCode = 0;
    lastKeyClickCode = 0;
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
    //NSLog(@"Time: %d", self.timeSeconds);
    self.gameTimeSeconds--;
    if(self.gameTimeSeconds > 0)
    {
        [self updateTimer];
        return;
    }
    [self stopTimer];
    // Buzzer - Audio Toolbox should work for this
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// This method must be implemented for the CB central manager delegate
- (void) centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state == CBCentralManagerStatePoweredOn)
    {
        // if the BT stack is powered on...
        NSLog(@"BT powered on");
        // Begin scanning for TI keys
        // No services are specified because the TI keys don't advertise
        // services by default
        NSLog(@"Scanning for peripherals");
        [central scanForPeripheralsWithServices:nil options:nil];
    } else
    {
        NSLog(@"BT is not on");
    }
}

// This method is implemented for the CB central manager delegate
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
        NSLog(@"Discovered TI BLE Sensor Tag");
        cbPeripheral = peripheral;
        [cbCentralManager stopScan];
        NSLog(@"Stopped scanning for peripherals");
        [cbCentralManager connectPeripheral:peripheral options:nil];
    }else
    {
        NSLog(@"Discovered something other than a TI Tag");
    }
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Connected to peripheral");
    peripheral.delegate = self;
    [peripheral discoverServices:[NSArray
                                  arrayWithObject:simpleKeyServiceUuid]];
    
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
    NSLog(@"Peripheral connection failed");
    NSLog(@"Scanning for peripherals");
    [cbCentralManager scanForPeripheralsWithServices:nil options:nil];
    
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
    NSLog(@"Scanning for peripherals");
    [cbCentralManager scanForPeripheralsWithServices:nil options:nil];
    
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
    NSLog(@"Scanning for peripherals");
    [cbCentralManager scanForPeripheralsWithServices:nil options:nil];
}

- (void) peripheral:(CBPeripheral *)peripheral
didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
              error:(NSError *)error
{
    if(error == nil)
    {
        NSLog(@"Notification subscription successful");
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
                    NSLog(@"Right Click");
                    self.visitorScoreValue++;
                    [self updateBoard];
                    break;
                case 2:
                    lastKeyClickCode = 2;
                    NSLog(@"Left Click");
                    self.homeScoreValue++;
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
    gameTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                 target:self
                                               selector:@selector(tickTimer)
                                               userInfo:nil repeats:YES];
}

- (void) stopTimer
{
    NSLog(@"Stopping timer");
    [gameTimer invalidate];
}

- (IBAction)homeScoreChange:(id)sender {
    self.homeScoreValue++;
    [self updateBoard];
}

- (IBAction)visitorSccoreChange:(id)sender {
    self.visitorScoreValue++;
    [self updateBoard];
}

- (IBAction)timeStartStop:(id)sender {
    if(gameTimer.isValid)
    {
        [self stopTimer];
        return;
    }
    [self startTimer];
}

- (IBAction)resetClick:(id)sender {
    [self stopTimer];
    self.homeScoreValue = 0;
    self.visitorScoreValue = 0;
    self.gameTimeSeconds = 15 * 60;
    [self updateBoard];
}


@end
