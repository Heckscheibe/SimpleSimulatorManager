# Simple Simulator Manager

Streamline your development workflow with the Simple Simulator Manager, designed to enhance your experience when working with Apple's simulators.

As a software developer targeting Apple's platform, scenarios arise where utilizing a real device for testing may not be feasible or preferred, especially during initial development phases or for external contractors working on behalf of a different company. The intricate process of device registration within the Apple developer portal adds complexity and effort, making simulators an appealing choice.

Developers often opt for Xcode's built-in simulators due to their swift feedback cycle, particularly when compared to deploying applications on a physical device. Additionally, debugging databases becomes more straightforward with local database files, eliminating the need for file transfers from external devices and facilitating inspection with tools such as [SQLiteBrowser](https://sqlitebrowser.org/) or [Realm Browser](https://apps.apple.com/de/app/realm-browser/id1007457278?mt=12).

However, locating your app's folder in the local file system poses a challenge. Enter the Simple Simulator Manager, a tool crafted to assist in this aspect!

This tool simplifies the process by offering an intuitive interface for managing apps installed on local simulators. 

## Current features include:
- Comprehensive list of installed simulators, categorized by device type and OS version
- Swift access to simulator and application folders
- Effortless navigation to app folders installed on simulators
- Option to Show/Hide platforms in the list

## Security and Privacy:
To access the local file system, Simple Simulator Manager disables the [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime) of macOS and turns off the app sandbox. This involves a potentially risky entitlement. The entire code of the app is openly available in this repository, allowing users to review it and ensure that none of their data is used inappropriately or sent anywhere. The app operates entirely offline, ensuring a secure and private development environment.


**Note:** While Simple Simulator Manager facilitates efficient local testing, it is essential to conduct thorough testing on real devices before releasing your apps. ;)

*Inspired by [XSimulatorMngr](https://github.com/wcb133/XSimulatorMngr). I have used this program before, and it helped me a lot.*
