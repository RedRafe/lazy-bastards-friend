# Factorio Mod Template

A ready-to-use template for Factorio mods

---
### **1. Usage**

#### **1.0.1 Downloading the template**
Download the repository, unzip it, and put it in your Factorio mods directory, in your developing subfolder (any name can be used). The directory structure should look like this:

```bash
  factorio
  ├── config
  ├── mods                                # main mods folder
  │   ├── mod-list.json                   # list of enabled mods
  │   ├── mod-settings.dat                # your stored mods' settings
  │   ├── mod-A_1.0.0.zip                 # any mod
  │   ├── mod-B_1.0.0.zip                 # any mod
  │   ├── ...        
  │   └── dev                             # developing subfolder
  │       └── factorio-mod-template       # unzipped template       
  ├── saves
  ├── scenarios
  └── ...
```


#### **1.0.2 Renaming**
Remember to change the mod's _name_, _author_ and _hyperlinks_ in the `info.json` as well. 

> Mod's name must not include spaces in its internal name

> The developing subdirectory and your mod's folder name can have any name

#### **1.0.3 Exporting for Test and Distribution**
If you're using Visual Studio Code, you can run any of the already available tasks to automatically export your mod in the Factorio convention.

> `archive/`, `.vscode/` and `.gitignore` will **not** be exported/copied along with your mod.

The task **`export`** will export the mod directly into the main mod folder in `.zip` format: `factorio/mods/factorio-mod-template_0.1.0.zip`, using the `name` and `version` specified in the `info.json`, ready to be used or uploaded to the Mod Portal. Will also overwrite any existent zipped mod with the same name and version.

> task:export is particularly useful for data-stages and distribution

The task **`copy`** will export the mod directly into the main mod folder just as it is (unzipped): `factorio/mods/factorio-mod-template_0.1.0`, using the `name` and `version` specified in the `info.json`, ready to be used. Will also overwrite any existent mod folder with the same name and version.

> task:copy is particularly useful for testing, especially runtime scripts

The task **`clear`** will remove any instance of matching `name` and `version` of your mod from the `factorio/mods` directory, if you need a cleanup.

---

### 2. **Resources**

- Markdown: [Basic Syntax](https://www.markdownguide.org/basic-syntax/)
- Factorio:
  - [Data raw](https://wiki.factorio.com/Prototype_definitions): documentation of Factorio's prototypes at data stage
  - [Runtime docs](https://lua-api.factorio.com/latest/): documentation of classes and events at runtime
  - [Mod portal](https://mods.factorio.com): the official Factorio Mod Portal
- Lua 5.2 [manual](https://www.lua.org/manual/5.2/manual.html)
- Visual Studio Code: [setting up tasks](https://go.microsoft.com/fwlink/?LinkId=733558)

---

*Join my [Discord](https://discord.gg/pq6bWs8KTY)*
