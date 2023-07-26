import * as glob from "glob";
import * as path from "https://deno.land/std@0.194.0/path/mod.ts";
import * as xcode from "xcode";

const project = xcode.project(Deno.args[0]);

console.log(Deno.args[0]);

// Find AppDelegate.swift
const filePaths = glob.sync(path.join("**", "AppDelegate.swift"));

project.parse(async (err: any) => {
  if (err) {
    console.error(err);
    return;
  }

  const targets = project.pbxNativeTargetSection();

  let hasNotificationServiceExtension = false;

  for (let key in targets) {
    const target = targets[key];
    if (target && target.productType === "com.apple.product-type.app-extension") {
      const name = target.name.replace(/"/g, "");
      if (name.endsWith("NotificationServiceExtension")) {
        hasNotificationServiceExtension = true;
        break;
      }
    }
  }

  if (hasNotificationServiceExtension) {
    console.log("Notification Service Extension found");
  } else {
    console.log("Notification Service Extension not found");
  }


  for (const filePath of filePaths) {
    const contents = await Deno.readTextFile(filePath);
    if (contents.includes("func userNotificationCenter(")) {
      console.log("Required method found in AppDelegate.swift");
    } else {
      console.log("Required method not found in AppDelegate.swift");
    }
  }
});