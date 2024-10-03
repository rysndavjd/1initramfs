# Copyright 2024 rysndavjd
# Distributed under the terms of the GNU General Public License v2
# 1initramfs

include config.mk

all: 

clean: 
	rm -rf 1initramfs-${VERSION} 1initramfs-${VERSION}.tar.gz

release: clean
	mkdir -p 1initramfs-${VERSION}
	cp -R README.md LICENSE Makefile config.mk 1initramfs.sh \
	1initramfs.conf 1initramfs-${VERSION}
	sed -i 's/shversion="git"/shversion="${VERSION}"/' 1initramfs-${VERSION}/1initramfs.sh
	tar -cf 1initramfs-${VERSION}.tar 1initramfs-${VERSION}
	gzip 1initramfs-${VERSION}.tar
	rm -rf 1initramfs-${VERSION} 

install: 
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f 1initramfs.sh ${DESTDIR}${PREFIX}/bin/1initramfs
	sed -i 's/shversion="git"/shversion='$VERSION'/' ${DESTDIR}${PREFIX}/bin/1initramfs
	chmod 755 ${DESTDIR}${PREFIX}/bin/1initramfs
	mkdir -p ${DESTDIR}/etc/default
	cp -f 1initramfs.conf ${DESTDIR}/etc/default/1initramfs
	chmod 644 ${DESTDIR}/etc/default/1initramfs

uninstall:
	rm -fr ${DESTDIR}${PREFIX}/bin/1initramfs

.PHONY: release install uninstall
