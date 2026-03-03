# ===========================================================================
# Stage 1: Build TeX Live installation
# ===========================================================================
# Pinned for reproducibility. To update, run:
#   docker pull debian:trixie-slim
#   docker inspect --format='{{index .RepoDigests 0}}' debian:trixie-slim
# Then replace the digest below.
# FROM debian:trixie-slim@sha256:REPLACE_WITH_ACTUAL_DIGEST AS texlive-builder

FROM debian:trixie-slim AS texlive-builder

ENV DEBIAN_FRONTEND=noninteractive

# Only the minimal tools needed to bootstrap TeX Live
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        perl \
        fontconfig \
    && rm -rf /var/lib/apt/lists/*

# Install vanilla TeX Live from TUG with minimal scheme
RUN wget -qO /tmp/install-tl-unx.tar.gz https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz && \
    mkdir /tmp/install-tl && \
    tar -xzf /tmp/install-tl-unx.tar.gz -C /tmp/install-tl --strip-components=1 && \
    perl /tmp/install-tl/install-tl --no-interaction --scheme scheme-basic && \
    # Create a symlink so we don't have to guess the year in the next step
    ln -s /usr/local/texlive/*/bin/aarch64-linux /usr/local/texlive/bin && \
    rm -rf /tmp/install-tl /tmp/install-tl-unx.tar.gz

# Add to PATH using the symlink
ENV PATH="/usr/local/texlive/bin:${PATH}"

# ---------------------------------------------------------------------------
# Install all packages in one layer.
# We pass --no-execute-actions to suppress fmtutil/updmap during install
# (partial installs cause format rebuilds to fail). Then we run mktexlsr
# and fmtutil-sys once at the end with everything in place.
# ---------------------------------------------------------------------------
ENV TEXLIVE_INSTALL_NO_RESUME=1

RUN tlmgr option -- autobackup 0 && \
    tlmgr install --no-execute-actions \
    #                                                                        \
    # --- Engine: LuaLaTeX ------------------------------------------------- \
    luatex \
    luahbtex \
    luaotfload \
    luatexbase \
    luacolor \
    lualatex-math \
    latexmk \
    #                                                                        \
    # --- Hyphenation base (required for fmtutil format rebuilds) ---------- \
    hyphen-base \
    #                                                                        \
    # --- Core LaTeX infrastructure ---------------------------------------- \
    latex \
    latex-bin \
    latex-fonts \
    latexconfig \
    extsizes \
    etoolbox \
    iftex \
    infwarerr \
    kvoptions \
    kvsetkeys \
    kvdefinekeys \
    ltxcmds \
    pdftexcmds \
    xkeyval \
    l3kernel \
    l3packages \
    l3backend \
    #                                                                        \
    # --- Fonts ------------------------------------------------------------ \
    fontspec \
    ec \
    cm \
    cm-super \
    lm \
    lm-math \
    amsfonts \
    unicode-math \
    gnu-freefont \
    sourcecodepro \
    tex-gyre \
    qualitype \
    emoji \
    twemoji-colr \
    #                                                                        \
    # --- Language / Hyphenation ------------------------------------------- \
    babel \
    babel-english \
    babel-french \
    babel-german \
    hyphen-english \
    hyphen-french \
    hyphen-german \
    hyph-utf8 \
    csquotes \
    #                                                                        \
    # --- Page layout & headers -------------------------------------------- \
    geometry \
    fancyhdr \
    #                                                                        \
    # --- Color & graphics ------------------------------------------------- \
    xcolor \
    graphics \
    graphics-cfg \
    graphics-def \
    svg \
    transparent \
    trimspaces \
    #                                                                        \
    # --- TikZ / PGF ------------------------------------------------------ \
    pgf \
    tikzfill \
    tikz-cd \
    pgfplots \
    spath3 \
    #                                                                        \
    # --- tcolorbox and ecosystem ------------------------------------------ \
    tcolorbox \
    environ \
    pdfcol \
    listings \
    minted \
    fvextra \
    fancyvrb \
    float \
    ifplatform \
    catchfile \
    upquote \
    lineno \
    framed \
    #                                                                        \
    # --- Tables ----------------------------------------------------------- \
    tabularray \
    ninecolors \
    #                                                                        \
    # --- Bytefield -------------------------------------------------------- \
    bytefield \
    #                                                                        \
    # --- Hyperlinks & bookmarks ------------------------------------------ \
    hyperref \
    url \
    bookmark \
    refcount \
    rerunfilecheck \
    hycolor \
    auxhook \
    intcalc \
    etexcmds \
    bitset \
    bigintcalc \
    atbegshi \
    atveryend \
    letltxmacro \
    pdfescape \
    uniquecounter \
    gettitlestring \
    #                                                                        \
    # --- Math ------------------------------------------------------------- \
    amsmath \
    amscls \
    nicematrix \
    siunitx \
    translations \
    #                                                                        \
    # --- Bibliography (biblatex + biber) ---------------------------------- \
    biblatex \
    biber \
    logreq \
    #                                                                        \
    # --- Lists ------------------------------------------------------------ \
    enumitem \
    #                                                                        \
    # --- Placeholder text ------------------------------------------------- \
    lipsum \
    #                                                                        \
    # --- Sensible standard extras ---------------------------------------- \
    tools \
    oberdiek \
    epstopdf-pkg \
    grfext \
    stringenc \
    carlisle \
    xstring \
    eso-pic \
    multirow \
    booktabs \
    caption \
    microtype \
    #                                                                        \
    # --- Formatting ------------------------------------------------------- \
    latexindent \
    && mktexlsr \
    && updmap-sys \
    && fmtutil-sys --all



# ===========================================================================
# Stage 2: Runtime image
# ===========================================================================
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# All system packages + locale setup in a single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tzdata \
        locales \
        curl \
        git \
        inkscape \
        tree \
        poppler-utils \
        ca-certificates \
        wget \
        perl \
        libfile-homedir-perl \
        libyaml-tiny-perl \
        liblog-log4perl-perl \
        libunicode-linebreak-perl \
        fontconfig \
        apt-transport-https \
        gnupg \
        jq \
        npm \
        python3 \
        python3-pip \
        python3-venv \
    && ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime \
    && dpkg-reconfigure --frontend noninteractive tzdata \
    && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Copy the complete TeX Live tree
COPY --from=texlive-builder /usr/local/texlive /usr/local/texlive

# Use the symlink created in Stage 1 instead of hardcoding 2025
ENV PATH="/usr/local/texlive/bin:${PATH}"

# Install MkDocs with Material theme
RUN pip install --break-system-packages mkdocs-material

# Rebuild font cache so fontspec/luaotfload find TeX Live fonts
RUN fc-cache -fv

# Install code assistants
ENV PATH="/root/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN npm install -g @google/gemini-cli
RUN npm install -g @google/jules

WORKDIR /workspaces
