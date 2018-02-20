#!/bin/bash
 ##############################################################################
 #                      parabola-riscv64-bootstrap                            #
 #                                                                            #
 #    Copyright (C) 2018  Andreas Grapentin                                   #
 #                                                                            #
 #    This program is free software: you can redistribute it and/or modify    #
 #    it under the terms of the GNU General Public License as published by    #
 #    the Free Software Foundation, either version 3 of the License, or       #
 #    (at your option) any later version.                                     #
 #                                                                            #
 #    This program is distributed in the hope that it will be useful,         #
 #    but WITHOUT ANY WARRANTY; without even the implied warranty of          #
 #    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
 #    GNU General Public License for more details.                            #
 #                                                                            #
 #    You should have received a copy of the GNU General Public License       #
 #    along with this program.  If not, see <http://www.gnu.org/licenses/>.   #
 ##############################################################################

set -euo pipefail

msg "preparing a $_arch cross makepkg environment"

if [ ! -f "$_makepkgdir"/makepkg-$_arch.sh ]; then
  # create required directories
  mkdir -pv "$_makepkgdir"/makepkg-$_arch
  pushd "$_makepkgdir"/makepkg-$_arch >/dev/null

  _pkgver=$(pacman -Qi pacman | grep '^Version' | cut -d':' -f2 | tr -d [:space:])

  # fetch pacman package to excract makepkg
  pacman -Sw --noconfirm --cachedir . pacman
  mkdir tmp && bsdtar -C tmp -xf pacman-$_pkgver-*.pkg.tar.xz

  # install makepkg
  cp -av tmp/usr/bin/makepkg "$_makepkgdir"/makepkg-$_arch.sh

  # patch run_pacman in makepkg, we cannot pass the pacman root to it as parameter ATM
  sed -i "s#\"\$PACMAN_PATH\"#& --config $_chrootdir/etc/pacman.conf -r $_chrootdir#" \
    "$_makepkgdir"/makepkg-$_arch.sh

  popd >/dev/null

  # rm -rf "$_makepkgdir"/makepkg-$_arch
fi

# create temporary makepkg.conf
cat > "$_makepkgdir"/makepkg-$_arch.conf << EOF
DLAGENTS=('ftp::/usr/bin/curl -fC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
          'http::/usr/bin/curl -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'https::/usr/bin/curl -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'rsync::/usr/bin/rsync --no-motd -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
VCSCLIENTS=('bzr::bzr'
            'git::git'
            'hg::mercurial'
            'svn::subversion')
CARCH="$_arch"
CHOST="$_target"
CPPFLAGS="-D_FORTIFY_SOURCE=2"
CFLAGS="-O2 -pipe -fstack-protector-strong -fno-plt"
CXXFLAGS="-O2 -pipe -fstack-protector-strong -fno-plt"
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
DEBUG_CFLAGS="-g -fvar-tracking-assignments"
DEBUG_CXXFLAGS="-g -fvar-tracking-assignments"
BUILDENV=(!distcc color !ccache check !sign)
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !optipng !upx !debug)
INTEGRITY_CHECK=(md5)
STRIP_BINARIES="--strip-all"
STRIP_SHARED="--strip-unneeded"
STRIP_STATIC="--strip-debug"
MAN_DIRS=({usr{,/local}{,/share},opt/*}/{man,info})
DOC_DIRS=(usr/{,local/}{,share/}{doc,gtk-doc} opt/*/{doc,gtk-doc})
PURGE_TARGETS=(usr/{,share}/info/dir .packlist *.pod)
COMPRESSGZ=(gzip -c -f -n)
COMPRESSBZ2=(bzip2 -c -f)
COMPRESSXZ=(xz -c -z -)
COMPRESSLRZ=(lrzip -q)
COMPRESSLZO=(lzop -q)
COMPRESSZ=(compress -c -f)
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'
EOF

if [ "x$_arch" != "x$(uname -m)" ]; then
  # make built packages available in sysroot
  _sysroot=$($_target-gcc --print-sysroot)
  mkdir -p $_chrootdir/usr
  umount "$_sysroot"/usr || true
  mount -o bind $_chrootdir/usr $_sysroot/usr
  mkdir -p $_chrootdir/usr/bin
  cp -v $(which qemu-$_arch-static) $_sysroot/usr/bin
fi
