################################################################################
# The Unofficial RedPill Helper v0.12                                          #
################################################################################

Now with support for RedPill extensions using the `ext` action. 

See section Changelog for changes!

*** Please do not ask to add <platform_version> with configurations for other 
redpill-load repositories, please add them to your own `user_config.json` ***


## Features / Configuration

- Creates a OCI Container (~= Docker) image based toolchain

- Caching of downloaded build components:
   - Takes care of downloading (and caching) the required sources to compile
     redpill-lkm.ko 
     and the required OS packages that the build process depends on
   - Performs integrity check of kernel/toolkit-dev version required to build 
     redpill-lkm
   - Caches .pat downloads from inside the container on the host

- Flexible configuration:
   - Configuration is done in the JSON file `global_config.json`; custom 
     <platform_version> entries can be added underneath the `build_configs` 
     block. Make sure the `id` is unique per block and does not use a space, 
     single quote or double quote character or any odd special character, as it 
     might break the the script! You can add the same <platform_version> 
     multiple times with different `id` values that point to different 
     `user_config.json` (used by redpill-load)
   - The default `global_config.json` contains platform versions supported by 
     the official redpill-load repository. Please create new <platform_version> 
     and point it to custom repositories if needed
   - Supports overriding settings from `global_config.json` in a user specific
     `custom_config.json`. The file must be created manually and supports all 
     fields that `global_config.json` has. If the `custom_config.json`  exists, 
     the configurations are merged. Values from the `custom_config.json` always 
     override the values in the `global_config.json`
     
     NB. Entries in the `"build_configs":` array must be complete (not just 
     single keys and their values) and are matched by `id`.
     The `docker` element must exist, and has a different behaviour to 
     `build_configs` entries, as only the values you want to override need to be 
     declared in the `custom_config.json`

   - Supports binding a local redpill-lkm folder into the container
     
     Set:

     `"docker.local_rp_lkm_use": "true"`

        and

     `"docker.local_rp_lkm_path": "path/to/rp-lkm"`
     
     If set to "true" the auto action will not pull the latest redpill-lkm 
     sources!

   - Supports binding a local redpill-load folder into the container

     Set:
 
     `"docker.local_rp_load_use": "true"`

        and

     `"docker.local_rp_load_path": "path/to/rp-load"`

     If set to "true" the auto action will not pull latest redpill-load sources!

   - Supports custom mounts

     Set:

     `"docker.use_custom_bind_mounts":` to `"true"`

     and add your custom bind-mounts in `"docker.custom_bind_mounts"`

   - Supports use of make target to specify the redpill.ko build configuration

     Set <platform_version>.redpill_lkm_make_target to `dev-v6`, `dev-v7`,
     `test-v6`, `test-v7`, `prod-v6` or `prod-v7`
     
     Make sure to use the -v6 ones on DSM6 build and -v7 on DSM7 build.
     By default the targets `dev-v6` and `dev-v7` are used.

      - dev: all symbols included, debug messages included
      - test: fully stripped with only warning & above (no debugs or info)
      - prod: fully stripped with no debug messages


- Cleanup of Docker Images and Build Caches:
  - Supports cleanup of old image versions and the build cache per 
    <platform_version>, or `all` of them at once.
  - Supports auto clean of old image versions and the build cache for the 
    current build image
    
    Set: `"docker.auto_clean": "true"`

  - Option to configure if the build cache is used or not: 
    `"docker.use_build_cache"`
  - Option to specify if "clean all" should delete all or only orphaned images
  - Caches the redpill-load custom folder, including downloaded extensions

### Usage

1. Edit `<platform>_user_config.json` that matches your <build_config_id>
   according https://github.com/RedPill-TTG/redpill-load and place it in the
   same folder as `rp-helper.sh`

2. Build the image for the platform and version you want:
   `./rp-helper.sh build <build_config_id>`

3. Optional: add extensions using the previously built image for a platform and 
   version (Repeat until all required extensions are added):

   `./rp-helper.sh ext <build_config_id> add <url_of_extension_to_add>`

4. Run a container based on the previously built image for the platform and
   version you want:

   `./rp-helper.sh auto <build_config_id>`

You can also use `./rp-helper.sh run <build_config_id>` to get a bash prompt, 
modify whatever you want and execute `make -C /opt/ build_all` to build the 
boot loader image.

After step 4 the redpill load image should be built and can be found in the 
host folder "images".

Please do not modify any values in `global_config.json`. Instead create and 
modify your personal `user_config.json` according your needs! This is where 
you should add other redpill-load repositories if you wish.


#### Actions

Run `./rp-helper.sh` to get the list of supported ids for the <build_config_id>
parameter (the list will show the merged list of ids of `global_config.json` 
and `user_config.json`).

Usage: ./rp-helper.sh <action> <platform version> [extension manager arguments]

Actions: build, ext, auto, run, clean

- build:    Build the redpill-helper image for the specified build config id

- ext:      Manage extensions within the specified build config id container.
            The modifications will apply to all build configs!

- auto:     Starts the redpill-helper container using the previously built 
            redpill-helper image for the specified buid config id. Updates 
            redpill sources and builds the bootloader image automaticaly and
            end the container once done

- run:      Starts the redpill-helper container using the previously built 
            redpill-helper image for the specified build config id with
            an interactive bash terminal

- clean:    Removes old/dangling images and the build cache for a given 
            build config id. Use `all` as build config id to remove images and
            build caches for all build configs.
            NB `"docker.clean_images": "all"` only affects `clean all`

Available build config ids:
---------------------
bromolow-6.2.4-25556
bromolow-7.0-41222
apollolake-6.2.4-25556
apollolake-7.0-41890

NB. these are the platform versions supported by TTG. Others can be added in the 
`user_config.json`.

## Examples:
### Build toolchain image

For Bromolow 6.2.4   : `./rp-helper.sh build bromolow-6.2.4-25556`
For Bromolow 7.0     : `./rp-helper.sh build bromolow-7.0-41222`
For Apollolake 6.2.4 : `./rp-helper.sh build apollolake-6.2.4-25556`
For Apollolake 7.0   : `./rp-helper.sh build apollolake-7.0-41890`

## Manage extensions
Add extension    :  `./rp-helper.sh ext <build_config_id> add <extension_url>`
Update extension :  `./rp-helper.sh ext <build_config_id> update <extension_id>`
Remove extension :  `./rp-helper.sh ext <build_config_id> remove <extension_id>`

Read ext-manager help for further options:  `./rp-helper.sh ext <build_config_id>`

### Create redpill bootloader image

For Bromolow 6.2.4   : `./rp-helper.sh auto bromolow-6.2.4-25556`
For Bromolow 7.0     : `./rp-helper.sh auto bromolow-7.0-41222`
For Apollolake 6.2.4 : `./rp-helper.sh auto apollolake-6.2.4-25556`
For Apollolake 7.0   : `./rp-helper.sh auto apollolake-7.0-41890`

### Clean old redpill bootloader images and build cache

For Bromolow 6.2.4   : `./rp-helper.sh clean bromolow-6.2.4-25556`
For Bromolow 7.0     : `./rp-helper.sh clean bromolow-7.0-41222`
For Apollolake 6.2.4 : `./rp-helper.sh clean apollolake-6.2.4-25556`
For Apollolake 7.0   : `./rp-helper.sh clean apollolake-7.0-41890`
For all              : `./rp-helper.sh clean all`


## Change log

### v0.12:
- Changed name from redpill_tool_chain to rp-helper.
- Added "ext" action to manage redpill extensions.
- Added `custom_config.json` to externalize user specific configuration. The 
  settings override the settings of the `global_config.json`
- Changed the ordering of `"vid":` and `"pid":` in the 
  <build_config>_user_profile.json files.

### v0.11:
- Added Supports to bind a local redpill-lkm folder into the container

### v0.10:
- Added the additionaly required make target when building redpill.ko
- Added a new configuration item in <build_config>.redpill_lkm_make_target to 
  set the build target

### v0.9:
- Added sha256 cheksum for kernel and toolkit-dev downloads in 
  `global_config.json`. Breaking Change: the item `"download_urls"` is renamed
  to `"downloads"` and has a new structure. Make sure to allign your custom
  build_config> configurations to the new structure  when copying them into
  the `global_config.json`.
- Check checksum of kernel or toolkit-dev when building the image and fail if
  checksums missmatch. Will not delete the corrupt file!
- Added`"docker.custom_bind_mounts"` in `global_config.json` to add as many 
  custom bind-mounts as you want, set `"docker.use_custom_bind_mounts":` to 
  `"true"` to enable the feature. 
- Fixed: only download kernel or toolkit-dev required to build the image
  (always downloaded both before, but only used either one of them when 
  building the image)
- Added simple precondition check to see if required tools are available

### v0.8:
- From now on, only the platform version from the official redpill-load 
  repository are supported. Thus all DSM7.0.1 platform versions are removed
  from `global_config.json`.

### v0.7.3:
- Fixed usage of label that determins the redpill-tool-chain images for clean up
- Add `"docker.use_build_cache": "false"` to `global_config.json`
- Add `"docker.clean_images": "all"` to `global_config.json`

### v0.7.2:
- Added `auto_clean` to clean old images and build cache after building the image.

### v0.7.1:
- `clean` now cleans the build cache as well

### v0.7:
- Added DSM 7.0.1 support (from none TTG Repos)
- Addded `clean` to delete old images created with the toolchain image builder 0.7

### v0.6.2:
- Not sure, forget to take notes...
### v0.6.1:
- Not sure, forget to take notes...

### v0.6:
- removed `user_config.json.template`, as it was orphaned and people started to 
use it in an unintended way.
- new parameters in `global_config.json`:
  - `docker.local_rp_load_use`: wether to mount a local folder with redpill-load 
    into the build container (true/false)
  - `docker.local_rp_load_path`: path to the local copy of redpill-load to mount
    into the build container (absolute or relative path)
  - `build_configs[].user_config_json`: allows to define a user_config.json 
  per <build_config>

### v0.5.4:
-  Changed redpill-load sources for apollolake-7.0-41890 to
   https://github.com/RedPill-TTG/redpill-load.git and the master branch.

### v0.5.3:
-  Modified the Dockerfile to set mode +x for /entrypoint.sh.

### v0.5.2:
- Added an entrypoint script that updates the redill sources in the container, 
  executes the build and exits the container once finished.
- Added action "auto", which starts the entypoint script. If you are not activly
  developing on redpill, then this is the action you wil want to use.
- The action "run" retained the old behavior: it skips the entrypoint script and
  drops you in a  bash shell.This action is ment for devs.
- Deaktivated Docker build cache, to prevent changes in the redpill repos stay 
  undetected when building a new image.
- Refactored the in-contaienr Makefile inside to detect the kernel version for 
  redpill-load/ext/rp-lkm/redpill-linux-${KERNELVERSION}.ko from compiled redpill.

### v0.5.1:
- Not sure, forget to take notes...
### v0.5.0:
- Migrated from Make to Bash (requires `jq`, instead of `make` now ).
- Removed Synology toolchain, the tool chain now consists  of debian packages.
- Configuration is now done in the JSON file `global_config.json`.
- The configuration allows to specify own configurations -> just copy a block 
  underneath the `building_configs` block and make sure it has a unique value 
  for the `id` attribute. The `id` is used what actualy is used to determine 
  the <build_config id>.

### previous versions:
- It was implemented in `make` before. Forget to take notes.
