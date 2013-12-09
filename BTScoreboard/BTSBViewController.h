//
//  BTSBViewController.h
//  BTScoreboard
//
//  Created by Thomas Propst on 12/2/13.
//  Copyright (c) 2013 Thomas Propst. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <QuartzCore/CABase.h>

// The view controller is declared as the CB Central Manager Delegate
@interface BTSBViewController : UIViewController <CBCentralManagerDelegate, CBPeripheralDelegate>

@end
