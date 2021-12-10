git apply debian/patches/dynamically-link-tools.patch
git apply debian/patches/multiarch.patch
git apply debian/patches/rename-library.patch
git apply debian/patches/enable-fpic-for-static-lib.patch


rm -rf build
mkdir build
cd build
cmake ..
make -j`nproc` VERBOSE=1
sudo make install