---
title: "Tailwind CSS Breakpoints in Google Chrome Device Toolbar"
author: "Ally"
summary: "Setting up the Tailwind breakpoints by adding custom devices in Google Chrome's device toolbar for easier testing."
publishDate: 2022-05-27T18:53:26+0100
tags: [tailwind,tailwindcss]
draft: false
---

The following default breakpoints in Tailwind CSS are:

```text
name                   width
----------------------------
tailwind: 00 xs:       639
tailwind: 01 sm min:   640
tailwind: 02 sm max:   767
tailwind: 03 md min:   768
tailwind: 04 md max:   1023
tailwind: 05 lg min:   1024
tailwind: 06 lg max:   1279
tailwind: 07 xl min:   1280
tailwind: 08 xl max:   1535
tailwind: 09 2xl min:  1536
```

Open the Google Chrome Developer Tools and click on the device toolbar menu (blue device icon)

![Google Chrome Developer Tool Device Toolbar Icon](/img/articles/tailwind-breakpoints-google-chrome-devices/device-toolbar-menu-icon.png)

At the top of the web-page, below the URL bar click on the Dimensions menu and then click Edit at the bottom of the menu.

An Emulated Devices window will open developer tools window.

![Emulated Devices](/img/articles/tailwind-breakpoints-google-chrome-devices/edit-devices.png)

Add the devices with the following names and widths above, I recommend the device height to be around half of the height of your display.

![Emulated Devices](/img/articles/tailwind-breakpoints-google-chrome-devices/create-device.png)

I made the following [codepen](https://codepen.io/alistaircol/full/vYmKQab) and use in the apps I work on to debug on different viewports.
