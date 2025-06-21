include /usr/share/dpkg/pkg-info.mk

PACKAGE = pve-firmware

BUILDDIR ?= $(PACKAGE)-$(DEB_VERSION_UPSTREAM)
ORIG_SRC_TAR=$(PACKAGE)_$(DEB_VERSION_UPSTREAM).orig.tar.gz

DSC=$(PACKAGE)_$(DEB_VERSION_UPSTREAM_REVISION).dsc
FW_DEB=$(PACKAGE)_$(DEB_VERSION)_all.deb
DEBS=$(FW_DEB)

.PHONY: deb
deb: $(DEBS)

$(FW_DEB): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -b -us -uc

.PHONY: dsc
dsc:
	$(MAKE) clean
	$(MAKE) $(DSC)
	lintian $(DSC)

$(DSC): $(ORIG_SRC_TAR) $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -S -us -uc -d

sbuild: $(DSC)
	sbuild $(DSC)

# NOTE: when collapsing FW lists keep major.minor still separated, so we can sunset the older ones
# without user impact safely. The last oldstable list needs to be kept avoid breakage on upgrade
.PHONY: fw.list
fw.list: fwlist-5.15.x.y-pve
fw.list: fwlist-iwlwifi-extra
fw.list: fwlist-6.2.2-1-pve
fw.list: fwlist-6.2.6-1-pve
fw.list: fwlist-6.2.16-11-pve
fw.list: fwlist-6.5.3-1-pve
fw.list: fwlist-6.8.1-1-pve
fw.list: fwlist-6.8.8-1-pve
fw.list: fwlist-6.8.12-7-pve
fw.list: fwlist-6.11.11-2-pve
fw.list: fwlist-6.12.33-1-pve
fw.list: fwlist-6.14.4-1-pve
	rm -f $@.tmp $@
	sort -u $^ > $@.tmp
	mv $@.tmp $@

$(ORIG_SRC_TAR): $(BUILDDIR)
	tar czf $(ORIG_SRC_TAR) --exclude="$(BUILDDIR)/debian" $(BUILDDIR)

$(BUILDDIR): linux-firmware.git/WHENCE dvb-firmware.git/README fw.list
	rm -rf $@ $@.tmp
	mkdir -p $@.tmp/lib/firmware
	cp -a debian $@.tmp
	echo "git clone https://github.com/YuxuanZuo/pve-firmware.git\\ngit checkout $$(git rev-parse HEAD)" >$@.tmp/debian/SOURCE
	cd linux-firmware.git; ./copy-firmware.sh -v ../$@.tmp/lib/firmware/
	./assemble-firmware.pl fw.list $@.tmp/lib/firmware
	find $@.tmp/lib/firmware -empty -type d -delete
	install -d $@.tmp/usr/share/doc/pve-firmware
	cp linux-firmware.git/WHENCE $@.tmp/usr/share/doc/pve-firmware/README
	install -d $@.tmp/usr/share/doc/pve-firmware/licenses
	cp linux-firmware.git/LICEN[CS]E* $@.tmp/usr/share/doc/pve-firmware/licenses
	# we only compress big ones that almost definitively ain't required in the initrd
	# or are so big and unbuyable (netronome...)
	cd $@.tmp/lib/firmware; find . -type f \( -name 'i[wb][lt]*' -o -path '*/netronome/*' \) -print0 | xargs -0 -n1 -P0 -- xz -C crc32
	cd $@.tmp/lib/firmware; find . -xtype l -print0 | xargs -0 -n1 -P0 -- sh -c 'ln -sf "$$(readlink "$$0").xz" "$$0"; mv "$$0" "$$0.xz"'
	mv $@.tmp $@

# upgrade to current master
.PHONY: update_modules
update_modules: submodule
	git submodule foreach 'git pull --ff-only origin master'

# make sure submodules were initialized
.PHONY: submodule
submodule dvb-firmware.git/README linux-firmware.git/WHENCE:
	test -f "linux-firmware.git/WHENCE" || git submodule update --init

.PHONY: upload
upload: UPLOAD_DIST ?= $(DEB_DISTRIBUTION)
upload: $(DEBS)
	tar cf - $(DEBS) | ssh repoman@repo.proxmox.com -- upload --product pve,pmg,pbs,pdm --dist $(UPLOAD_DIST)

.PHONY: clean
clean:
	rm -rf $(PACKAGE)-[0-9]*/
	rm -f $(PACKAGE)*.tar* *.deb *.dsc *.changes *.dsc *.buildinfo *.build
