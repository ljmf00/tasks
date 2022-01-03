FROM ljmf00/archlinux:latest

RUN sudo -u docker yay -Syy --noconfirm --needed \
    dstask aha npm git dtools dub ldc
