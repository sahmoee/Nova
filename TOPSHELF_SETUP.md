# Top Shelf Setup (Apple TV) — ELI5

Top Shelf is the big row that appears at the top of the Apple TV home screen when your app icon is in the top row. FrameTV can show Continue Watching and Recently Added there, and jump straight into a title.

I have written all the code for you (in the FrameTVTopShelf folder). Because a Top Shelf extension is a separate mini-app inside your app, Xcode has to create the target for you. Here is exactly what to do. It takes about 5 minutes.

## Step 1 — Add the extension target

1. Open FrameTV in Xcode.
2. Menu: File, New, Target.
3. Pick the tvOS tab at the top.
4. Choose TV Top Shelf Extension. Click Next.
5. Product Name: type FrameTVTopShelf (exactly).
6. Make sure Project is FrameTV and Embed in Application is FrameTV-tvOS.
7. Click Finish. If Xcode asks to activate a scheme, click Cancel (not Activate).

Xcode just created a folder with a template file. You will replace its contents with mine.

## Step 2 — Swap in my files

1. In the new FrameTVTopShelf group Xcode made, DELETE the template Swift file it created (usually ContentProvider.swift or ServiceProvider.swift). Choose Move to Trash.
2. Drag my three files from the FrameTVTopShelf folder into that group in Xcode:
   - TopShelfProvider.swift
   - Info.plist (replace the one Xcode made — choose Replace)
   - FrameTVTopShelf.entitlements
3. When dragging, make sure Target: FrameTVTopShelf is checked, and Copy items if needed is checked.

## Step 3 — Turn on the shared mailbox (App Group)

The Top Shelf needs to read the same shared data the widgets use.

1. Click the FrameTV project (top of the file list), then select the FrameTVTopShelf target.
2. Go to Signing and Capabilities.
3. Click + Capability, add App Groups.
4. Check the box next to group.com.frametv.shared.
   - If it is not listed, click + under App Groups and type it exactly.

## Step 4 — Point the Info.plist at my class (only if Xcode made its own)

If you replaced Info.plist with mine in Step 2, you can skip this. Otherwise, in the extension's Info.plist, under NSExtension, set:
- NSExtensionPointIdentifier to com.apple.tv-top-shelf
- NSExtensionPrincipalClass to $(PRODUCT_MODULE_NAME).TopShelfProvider

## Step 5 — Build and run on Apple TV

1. Clean build folder (Product menu, hold Option, Clean Build Folder).
2. Build and run the tvOS app once so it writes its library snapshot.
3. Go to the Apple TV home screen and move FrameTV into the very top row.
4. Hover on the FrameTV icon. Continue Watching and Recently Added should appear above it, and selecting one opens that title in FrameTV.

## If nothing shows

- The Top Shelf only shows once the app has saved a snapshot, so play or add something first.
- The app must be in the top row of the home screen.
- Double-check the App Group box is checked for the extension (Step 3). This is the most common miss.
