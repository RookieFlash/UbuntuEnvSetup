#!/bin/bash

set -e

LOG="setup_env.log"

# 日志打印
log() {
    echo -e "\e[36m`date +\"%Y-%m-%d %H:%M:%S\"`\e[33m [INFO] | $1 \e[0m"
    echo -e "`date +\"%Y-%m-%d %H:%M:%S\"`[INFO] $1" | tee -a $LOG
}

# 安装到 macchanger 这种会弹出对话框的软件，会出现：无法使用左键切换到 Yes 选项。
# 我是使用手动安装方式来解决的：sudo apt install macchanger。
# GPT给的建议是给 run() 加上 DEBIAN_FRONTEND=noninteractive - 未做验证。
run() {
    log "Running: $*"
    sudo bash -c "$*" 2>&1 | tee -a $LOG
}

update_system() {
    log "=== Updating system ==="
    run "apt update"
}

# -------------------------------------------------------------------------------------------------------
# 更换软件源
# -------------------------------------------------------------------------------------------------------
detect_best_mirror() {
    log "=== Detecting best APT mirror ==="

    declare -A mirrors=(
        ["aliyun"]="http://mirrors.aliyun.com/ubuntu/"
        ["tsinghua"]="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
        ["official"]="http://archive.ubuntu.com/ubuntu/"
    )

    local best_mirror=""
    local best_time=999999

    for name in "${!mirrors[@]}"; do
        local url="${mirrors[$name]}dists/jammy/Release"

        log "Testing $name mirror..."

        # 测试响应时间（秒）
        local time
        time=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 3 "$url")

        # 如果失败，time 可能为空
        if [ -z "$time" ]; then
            log "$name failed"
            continue
        fi

        log "$name response time: $time"

        # 转成整数比较（乘1000避免浮点）
        local time_ms
        time_ms=$(echo "$time * 1000" | bc | cut -d. -f1)

        if [ "$time_ms" -lt "$best_time" ]; then
            best_time=$time_ms
            best_mirror="${mirrors[$name]}"
        fi
    done

    if [ -z "$best_mirror" ]; then
        log "No mirror available, fallback to official"
        best_mirror="http://archive.ubuntu.com/ubuntu/"
    fi

    log "Best mirror selected: $best_mirror"

    echo "$best_mirror"
}

switch_apt_source_auto() {
    local mirror
    # mirror=$(detect_best_mirror)
    # detect_best_mirror 输出了日志 + 结果混在一起
    #   shell 的 $() 会捕获函数所有 stdout，而 log() 也在 stdout
    #   所以只取最后一行，避免出错
    mirror=$(detect_best_mirror | tail -n 1)

    log "Using mirror: $mirror"

    local backup="/etc/apt/sources.list.bak.$(date +%s)"

    run "cp /etc/apt/sources.list $backup"

    run "cat > /etc/apt/sources.list << EOF
deb $mirror jammy main restricted universe multiverse
deb $mirror jammy-updates main restricted universe multiverse
deb $mirror jammy-backports main restricted universe multiverse
deb $mirror jammy-security main restricted universe multiverse
EOF"

    run "apt update"
}

# -------------------------------------------------------------------------------------------------------
# 安装必备工具
# -------------------------------------------------------------------------------------------------------
install_base_tools() {
    log "=== Installing base tools ==="
    run "apt install -y \
        build-essential gcc g++ make cmake \
        git vim curl wget \
        net-tools iproute2 \
        htop tree unzip zip pkg-config \
        openssh-server npm locate copyq"
}

# -------------------------------------------------------------------------------------------------------
# 安装 python
# -------------------------------------------------------------------------------------------------------
install_python() {
    log "=== Installing Python environment ==="
    run "apt install -y python3 python3-pip python3-venv"
    run "pip3 install --user virtualenv ipython"
}

# -------------------------------------------------------------------------------------------------------
# 安装调试工具
# -------------------------------------------------------------------------------------------------------
install_debug_tools() {
    log "=== Installing debug tools ==="
    run "apt install -y \
        gdb strace ltrace \
        tcpdump tshark \
        lsof valgrind"
}

# -------------------------------------------------------------------------------------------------------
# 安装 网络工具
# -------------------------------------------------------------------------------------------------------
install_network_tools() {
    log "=== Installing network tools ==="
    run "apt install -y \
        iw wireless-tools \
        dnsmasq \
        iperf3 bridge-utils"
}

install_wifi_tools() {
    log "=== Installing WiFi advanced tools ==="
    run "apt install -y \
        aircrack-ng \
        macchanger"
}

# -------------------------------------------------------------------------------------------------------
# 安装内核相关软件工具
# -------------------------------------------------------------------------------------------------------
install_kernel_dev() {
    log "=== Installing kernel development tools ==="
    run "apt install -y \
        linux-headers-$(uname -r) \
        dkms \
        libnl-3-dev \
        libnl-genl-3-dev \
        libssl-dev"
}

# -------------------------------------------------------------------------------------------------------
# 安装编译工具
# -------------------------------------------------------------------------------------------------------
install_build_system() {
    log "=== Installing build system tools ==="
    run "apt install -y \
        autoconf automake libtool"
}

# -------------------------------------------------------------------------------------------------------
# 安装 VMTools
# -------------------------------------------------------------------------------------------------------
install_vmware_tools() {
    log "=== Installing VMware tools ==="
    run "apt install -y open-vm-tools open-vm-tools-desktop"
}

# -------------------------------------------------------------------------------------------------------
# 安装其他工具
# -------------------------------------------------------------------------------------------------------
install_optional_tools() {
    log "=== Installing optional tools ==="
    run "apt install -y tmux terminator"
}

# -------------------------------------------------------------------------------------------------------
# 安装字体 FiraCode
# -------------------------------------------------------------------------------------------------------
install_nerd_font_firacode() {
    log "=== Installing FiraCode Nerd Font ==="

    # -------------------------
    # 1. 检测是否已安装
    # -------------------------
    if fc-list | grep -qi "FiraCode Nerd Font"; then
        log "FiraCode Nerd Font already installed, skipping..."
        return
    fi

    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip"
    local zip_file="./FiraCode.zip"
    local tmp_zip="/tmp/FiraCode.zip"
    local tmp_dir="/tmp/firacode-font"
    local font_dir="/usr/local/share/fonts/FiraCode"

    run "apt install -y unzip fontconfig curl"

    run "rm -rf $tmp_dir"
    run "mkdir -p $tmp_dir"
    run "mkdir -p $font_dir"

    # -------------------------
    # 2. 判断是否已有本地 zip
    # -------------------------
    if [ -f "$zip_file" ]; then
        log "Found local FiraCode.zip, using it..."
        run "cp $zip_file $tmp_zip"
    else
        log "FiraCode.zip not found locally, downloading..."

        if ! run "curl -L --connect-timeout 10 $url -o $tmp_zip"; then
            log "Download failed, please manually place FiraCode.zip in current directory"
            exit 1
        fi
    fi

    # -------------------------
    # 3. 解压 & 安装
    # -------------------------
    run "unzip -o $tmp_zip -d $tmp_dir"

    run "find $tmp_dir -name '*.ttf' -o -name '*.otf' | xargs -I{} cp {} $font_dir/"

    run "fc-cache -fv"

    # -------------------------
    # 4. 清理
    # -------------------------
    run "rm -rf $tmp_zip $tmp_dir"

    log "FiraCode Nerd Font installed successfully"
}

# -------------------------------------------------------------------------------------------------------
# Neovim + Lazyvim
# 参考 https://osaerialrobot.top/2025/12/26/tree-sitter-lazyvim/index.html
# -------------------------------------------------------------------------------------------------------
configure_lazyvim_options() {
    log "=== Configuring LazyVim options.lua ==="

    local user=$1
    local home_dir

    if [ "$user" == "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$user"
    fi

    local config_dir="$home_dir/.config/nvim/lua/config"
    local file="$config_dir/options.lua"

    run "mkdir -p $config_dir"

    run "cat > $file << 'EOF'
-- Options are automatically loaded before lazy.nvim startup
-- Default options: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- 禁用自动格式化功能
vim.g.autoformat = false

vim.g.neovide_cursor_vfx_mode = "pixiedust"
-- vim.g.neovide_cursor_vfx_mode = "torpedo"
vim.g.neovide_cursor_vfx_particle_density = 100.0
vim.g.neovide_floating_shadow = false

-- 启用 IME 输入法支持
vim.g.neovide_input_ime = true

-- 打字时自动隐藏鼠标光标
vim.g.neovide_hide_mouse_when_typing = true

local opt = vim.opt

-- 禁用拼写检查
opt.spell = false

-- 设置隐藏级别
opt.conceallevel = 0

-- 自动折行
opt.wrap = true

-- 禁用相对行号
opt.relativenumber = false

-- Tab设置
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true

-- tags 示例
-- vim.opt.tags = {
--   "/path/aaa_tags",
--   "/path/bbb_tags",
-- }
EOF"

    #run "chown -R $user:$user $home_dir/.config/nvim 2>/dev/null || true"
}

configure_lazyvim_colorscheme() {
    log "=== Configuring LazyVim colorscheme (Catppuccin) ==="

    local user=$1
    local home_dir

    if [ "$user" == "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$user"
    fi

    local plugin_dir="$home_dir/.config/nvim/lua/plugins"
    local file="$plugin_dir/colorscheme.lua"

    run "mkdir -p $plugin_dir"

    run "cat > $file << 'EOF'
return {
  -- 设置 Catppuccin 为主题
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },

  -- Catppuccin 插件配置
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = true,
      styles = {
        comments = { "italic" },
      },
      integrations = {
        cmp = true,
        telescope = true,
      },
    },
  },
}
EOF"

    #run "chown -R $user:$user $home_dir/.config/nvim 2>/dev/null || true"
}

# 参考 https://osaerialrobot.top/2025/12/26/tree-sitter-lazyvim/index.html
install_tree_sitter() {
    log "=== Installing tree-sitter CLI (system-wide) ==="

    local url="https://github.com/tree-sitter/tree-sitter/releases/download/v0.24.0/tree-sitter-linux-x64.gz"
    local tmp_file="/tmp/tree-sitter.gz"
    local extracted="/tmp/tree-sitter"
    local install_path="/usr/local/bin/tree-sitter"

    # -------------------------
    # 1. 已安装检测（全局）
    # -------------------------
    if command -v tree-sitter >/dev/null 2>&1; then
        log "tree-sitter already installed, skipping..."
        return
    fi

    # -------------------------
    # 2. 下载（支持离线）
    # -------------------------
    if [ -f "./tree-sitter-linux-x64.gz" ]; then
        log "Using local tree-sitter package..."
        cp ./tree-sitter-linux-x64.gz "$tmp_file"
    else
        log "Downloading tree-sitter..."
        run "curl -L $url -o $tmp_file"
    fi

    # -------------------------
    # 3. 解压
    # -------------------------
    run "gzip -d -f $tmp_file"

    # -------------------------
    # 4. 安装到系统路径
    # -------------------------
    run "chmod +x $extracted"
    run "mv $extracted $install_path"

    # -------------------------
    # 5. 验证
    # -------------------------
    if command -v tree-sitter >/dev/null 2>&1; then
        log "tree-sitter installed successfully (system-wide)"
    else
        log "ERROR: tree-sitter installation failed"
        exit 1
    fi
}

install_neovim_lazyvim() {
    log "=== Installing Neovim + LazyVim (multi-user support) ==="

    local user_home
    user_home=$(eval echo "~$(whoami)")

    # -------------------------
    # 已安装检测（核心）
    # -------------------------
    if [ -f "$user_home/.config/nvim/lazy-lock.json" ]; then
        log "Neovim + LazyVim already installed, skipping..."
        return
    fi

    # -------------------------
    # 1. 安装依赖
    # -------------------------
    run "apt install -y git curl ripgrep fd-find"

    run "ln -sf $(which fdfind) /usr/local/bin/fd || true"

    # -------------------------
    # 2. 检查 Neovim
    # -------------------------
    install_neovim() {
        log "=== Installing Neovim (latest AppImage) ==="

        run "apt install -y curl fuse3"

        run "curl -LO https://github.com/neovim/neovim/releases/download/v0.12.1/nvim-linux-x86_64.appimage"

        run "chmod u+x nvim-linux-x86_64.appimage"

        run "cp nvim-linux-x86_64.appimage /usr/bin/nvim"
        run "chmod u+x /usr/bin/nvim"
    }

    if command -v nvim >/dev/null 2>&1; then
        ver=$(nvim --version | head -n1 | awk '{print $2}' | sed 's/v//')
        log "Detected Neovim version: $ver"

        if printf '%s\n' "0.9.0" "$ver" | sort -V -C; then
            log "Neovim already OK, skipping install"
        else
            log "Neovim too old, reinstalling..."
            install_neovim
        fi
    else
        install_neovim
    fi

    log "------ !!! Need To Run nvim for install plugins !!! ------"

    # -------------------------
    # 3. LazyVim 安装
    # -------------------------
    install_lazyvim_for_user() {
        local target_user=$1
        local home_dir

        if [ "$target_user" == "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$target_user"
        fi

        local nvim_dir="$home_dir/.config/nvim"
        # ✔ 已安装则跳过
        if [ -d "$nvim_dir/lazy/lazy.nvim" ]; then
            log "LazyVim already exists for $target_user, skipping..."
            return
        fi

        log "Installing LazyVim for $target_user"

        run "sudo -u $target_user mkdir -p $home_dir/.config"

        run "sudo -u $target_user git clone https://github.com/LazyVim/starter $home_dir/.config/nvim"

        # 清理 git 历史（官方推荐）
        run "sudo -u $target_user rm -rf $home_dir/.config/nvim/.git"
    }

    # -------------------------
    # 4. 配置（仅首次安装时执行）
    # -------------------------
    configure_if_needed() {
        local user=$1
        local home_dir

        if [ "$user" == "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi

        local nvim_dir="$home_dir/.config/nvim"

        # 只有 LazyVim 存在才配置
        if [ ! -d "$nvim_dir/lazy/lazy.nvim" ]; then
            return
        fi

        # options.lua 已存在则跳过（避免覆盖用户配置）
        if [ -f "$nvim_dir/lua/config/options.lua" ]; then
            log "options.lua already exists for $user, skipping..."
        else
            configure_lazyvim_options "$user"
        fi

        # colorscheme.lua 已存在则跳过
        if [ -f "$nvim_dir/lua/plugins/colorscheme.lua" ]; then
            log "colorscheme.lua already exists for $user, skipping..."
        else
            configure_lazyvim_colorscheme "$user"
        fi
    }


    # 当前普通用户 - 
    install_lazyvim_for_user "$(whoami)"
    configure_if_needed "$(whoami)"

    # root 用户
    install_lazyvim_for_user "root"
    configure_if_needed "root"
    
    install_tree_sitter

    log "Neovim And LazyVim installed."
    log "------ !!! Run nvim once to install plugins !!! ------"
}

# -------------------------------------------------------------------------------------------------------
# 安装BeyondCompare
# -------------------------------------------------------------------------------------------------------
install_beyond_compare() {
    log "=== Installing BeyondCompare ==="
    # 检查命令是否存在（最通用）
    if command -v bcompare >/dev/null 2>&1; then
        log "Beyond Compare already installed, skipping..."
        return
    fi

    local url="https://www.scootersoftware.com/bcompare-4.4.7.28397_amd64.deb"
    local deb_file="/tmp/bcompare.deb"
    run "curl -L $url -o $deb_file"
    run "apt install -y /tmp/bcompare-4.4.6.27483_amd64.deb"

    # 再次验证
    if command -v bcompare >/dev/null 2>&1; then
        log "Beyond Compare installed successfully"
    else
        log "ERROR: Beyond Compare installation failed"
        exit 1
    fi

    log "------ !!! BeyondCompare Need To Register !!! ------"
    log "
        Step 1: Run BeyondCompare

        Step 2: sudo sed -i "s/keexjEP3t4Mue23hrnuPtY4TdcsqNiJL-5174TsUdLmJSIXKfG2NGPwBL6vnRPddT7tH29qpkneX63DO9ECSPE9rzY1zhThHERg8lHM9IBFT+rVuiY823aQJuqzxCKIE1bcDqM4wgW01FH6oCBP1G4ub01xmb4BGSUG6ZrjxWHJyNLyIlGvOhoY2HAYzEtzYGwxFZn2JZ66o4RONkXjX0DF9EzsdUef3UAS+JQ+fCYReLawdjEe6tXCv88GKaaPKWxCeaUL9PejICQgRQOLGOZtZQkLgAelrOtehxz5ANOOqCaJgy2mJLQVLM5SJ9Dli909c5ybvEhVmIC0dc9dWH+/N9KmiLVlKMU7RJqnE+WXEEPI1SgglmfmLc1yVH7dqBb9ehOoKG9UE+HAE1YvH1XX2XVGeEqYUY-Tsk7YBTz0WpSpoYyPgx6Iki5KLtQ5G-aKP9eysnkuOAkrvHU8bLbGtZteGwJarev03PhfCioJL4OSqsmQGEvDbHFEbNl1qJtdwEriR+VNZts9vNNLk7UGfeNwIiqpxjk4Mn09nmSd8FhM4ifvcaIbNCRoMPGl6KU12iseSe+w+1kFsLhX+OhQM8WXcWV10cGqBzQE9OqOLUcg9n0krrR3KrohstS9smTwEx9olyLYppvC0p5i7dAx2deWvM1ZxKNs0BvcXGukR+/g" /usr/lib/beyondcompare/BCompare

        Step 3: 将下边的 Key 输入到 Beyond Compare 中
        --- BEGIN LICENSE KEY ---
        GXN1eh9FbDiX1ACdd7XKMV7hL7x0ClBJLUJ-zFfKofjaj2yxE53xauIfkqZ8FoLpcZ0Ux6McTyNmODDSvSIHLYhg1QkTxjCeSCk6ARz0ABJcnUmd3dZYJNWFyJun14rmGByRnVPL49QH+Rs0kjRGKCB-cb8IT4Gf0Ue9WMQ1A6t31MO9jmjoYUeoUmbeAQSofvuK8GN1rLRv7WXfUJ0uyvYlGLqzq1ZoJAJDyo0Kdr4ThF-IXcv2cxVyWVW1SaMq8GFosDEGThnY7C-SgNXW30jqAOgiRjKKRX9RuNeDMFqgP2cuf0NMvyMrMScnM1ZyiAaJJtzbxqN5hZOMClUTE+++
        --- END LICENSE KEY -----"
    log "Relate: https://gist.github.com/rise-worlds/5a5917780663aada8028f96b15057a67"
    log "------ !!! BeyondCompare Need To Register !!! ------"
}

# -------------------------------------------------------------------------------------------------------
# 安装 zsh & oh-my-zsh
# 在Ubuntu中脚本下载这两个插件失败，改为手动下载，放到与脚本同级目录下
# 由于是自动手动下载的 oh-my-zsh 插件，所以在安装之后的目录是代码版本号的，需要手动去掉版本号
# 注意使用 mv 来移动 zsh-syntax-highlighting/zsh-syntax-highlighting-0.8.0 下的文件到 zsh-syntax-highlighting/时要带上隐藏的文件：mv * .* ..
# -------------------------------------------------------------------------------------------------------
install_zsh_plugin() {
    local plugin_name=$1
    local zip_url=$2
    local user=$3
    local home_dir=$4

    local plugin_dir="$home_dir/.oh-my-zsh/custom/plugins/$plugin_name"
    local zip_file="./${plugin_name}.zip"
    local tmp_dir="/tmp/${plugin_name}"

    # -------------------------
    # 0. 已安装 → 跳过
    # -------------------------
    if [ -d "$plugin_dir" ]; then
        log "$plugin_name already installed"
        return
    fi

    # -------------------------
    # 1. 本地 zip 存在 → 用 zip
    # -------------------------
    if [ -f "$zip_file" ]; then
        log "Installing $plugin_name from local zip"

        run "rm -rf $tmp_dir"
        run "mkdir -p $tmp_dir"
        run "unzip -o $zip_file -d $tmp_dir"

        # GitHub zip 解压会带目录名
        local extracted
        extracted=$(find $tmp_dir -maxdepth 1 -type d -name "${plugin_name}*" | head -n 1)

        run "cp -r $extracted $plugin_dir"

        return
    fi

    # -------------------------
    # 2. 下载 zip
    # -------------------------
    log "zip download"

    run "wget $zip_url -O /tmp/${plugin_name}.zip"

    run "rm -rf $tmp_dir"
    run "mkdir -p $tmp_dir"
    run "unzip -o /tmp/${plugin_name}.zip -d $tmp_dir"

    local extracted
    extracted=$(find $tmp_dir -maxdepth 1 -type d -name "${plugin_name}*" | head -n 1)

    run "cp -r $extracted $plugin_dir"

    log "$plugin_name installed via zip"
}

install_zsh_ohmyzsh_all() {
    log "=== Installing Zsh + Oh My Zsh (root + user) ==="

    local CURRENT_USER=${SUDO_USER:-$(whoami)}
    local CURRENT_HOME
    CURRENT_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)

    local ROOT_HOME="/root"

    # -------------------------
    # 1. 安装 zsh
    # -------------------------
    if command -v zsh >/dev/null 2>&1; then
        log "zsh already installed"
    else
        run "apt install -y zsh git curl"
    fi

    # -------------------------
    # 2. 安装 oh-my-zsh（函数）
    # -------------------------
    install_ohmyzsh_for_user() {
        local user=$1
        local home_dir=$2

        if [ -d "$home_dir/.oh-my-zsh" ]; then
            log "Oh My Zsh already installed for $user"
            return
        fi

        log "Installing Oh My Zsh for $user"

        if ! run "sudo -u $user sh -c 'curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash'"; then
            log "Fallback: cloning via ghproxy"

            run "sudo -u $user git clone https://ghproxy.com/https://github.com/ohmyzsh/ohmyzsh.git $home_dir/.oh-my-zsh"
            run "sudo -u $user cp $home_dir/.oh-my-zsh/templates/zshrc.zsh-template $home_dir/.zshrc"
        fi
    }

    # -------------------------
    # 3. 安装插件（函数）
    # -------------------------
    install_plugins_for_user() {
        local user=$1
        local home_dir=$2

        run "sudo -u $user mkdir -p $home_dir/.oh-my-zsh/custom/plugins"

        # -------------------------
        # 1. 安装插件 - 历史命令自动补全
        # -------------------------
        install_zsh_plugin "zsh-autosuggestions" \
            "https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/v0.7.1.zip" \
            "$user" "$home_dir"

        # -------------------------
        # 2. 安装插件 - 命令行实时语法高亮
        # -------------------------
        install_zsh_plugin "zsh-syntax-highlighting" \
            "https://github.com/zsh-users/zsh-syntax-highlighting/archive/refs/tags/0.8.0.zip" \
            "$user" "$home_dir"
    }

    # -------------------------
    # 4. 配置 zshrc（函数）
    # -------------------------
    configure_zshrc_for_user() {
        local user=$1
        local home_dir=$2
        local zshrc="$home_dir/.zshrc"

        local zsh_dir="$home_dir/.oh-my-zsh"
        local theme_dir="$zsh_dir/custom/themes"
        local custom_theme="$theme_dir/robbyrussell-custom.zsh-theme"
        local base_theme="$zsh_dir/themes/robbyrussell.zsh-theme"

        # -------------------------
        # plugins
        # -------------------------
        if grep -q "^plugins=" "$zshrc"; then
            run "sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' $zshrc"
        else
            echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$zshrc"
        fi

        # -------------------------
        # theme 目录
        # -------------------------
        run "sudo -u $user mkdir -p $theme_dir"

        # -------------------------
        # 拷贝 theme（幂等）
        # -------------------------
        if [ ! -f "$custom_theme" ]; then
            run "cp $base_theme $custom_theme"
        fi

        # -------------------------
        # 修改 theme（只写一次）
        # -------------------------
        if ! grep -q "__CUSTOM_ZSH_PROMPT__" "$custom_theme"; then
            log "Patching theme for $user"

            cat >> "$custom_theme" << 'EOF'
# =========================
# Custom PROMPT
# =========================
# __CUSTOM_ZSH_PROMPT__

PROMPT="%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} )%{$fg[cyan]%}[ %{$fg[yellow]%}%~ | %{$fg[red]%}%?%{$fg[cyan]%} | %{$fg[white]%}%D{%Y-%m-%d %H:%M:%S} |%{$reset_color%}"
PROMPT+=' $(git_prompt_info)'
PROMPT+='%{$fg_bold[cyan]%}]'$'\n''$ %{$reset_color%}'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}%1{✗%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"

EOF
        else
            log "Theme already patched for $user"
        fi

        # -------------------------
        # 设置 theme
        # -------------------------
        if grep -q "^ZSH_THEME=" "$zshrc"; then
            run "sed -i 's/^ZSH_THEME=.*/ZSH_THEME=\"robbyrussell-custom\"/' $zshrc"
        else
            echo 'ZSH_THEME="robbyrussell-custom"' >> "$zshrc"
        fi
    }

    # -------------------------
    # 执行（普通用户）
    # -------------------------
    install_ohmyzsh_for_user "$CURRENT_USER" "$CURRENT_HOME"
    install_plugins_for_user "$CURRENT_USER" "$CURRENT_HOME"
    configure_zshrc_for_user "$CURRENT_USER" "$CURRENT_HOME"

    # -------------------------
    # 执行（root）
    # -------------------------
    install_ohmyzsh_for_user "root" "$ROOT_HOME"
    install_plugins_for_user "root" "$ROOT_HOME"
    configure_zshrc_for_user "root" "$ROOT_HOME"

    log "Zsh + Oh My Zsh installation and setup completed for root and $CURRENT_USER"
}


# -------------------------------------------------------------------------------------------------------
# 给 .bashrc 配置 PS1
# -------------------------------------------------------------------------------------------------------
configure_bash_ps1() {
    log "=== Configuring bash PS1 (root + user) ==="

    local CURRENT_USER=${SUDO_USER:-$(whoami)}
    local CURRENT_HOME
    CURRENT_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)

    local ROOT_HOME="/root"

    setup_ps1_for_user() {
        local user=$1
        local home_dir=$2
        local bashrc="$home_dir/.bashrc"

        log "Configuring PS1 for $user"

        # -------------------------
        # 1. 确保 git-prompt 存在
        # -------------------------
        run "apt install -y git"

        # Ubuntu路径
        local git_prompt="/usr/lib/git-core/git-sh-prompt"

        # -------------------------
        # 2. 写入 PS1（避免重复）
        # -------------------------
        if grep -q "__CUSTOM_PS1__" "$bashrc"; then
            log "PS1 already configured for $user"
            return
        fi

        run "cat >> $bashrc << 'EOF'

# __CUSTOM_PS1__
if [ -f /usr/lib/git-core/git-sh-prompt ]; then
    source /usr/lib/git-core/git-sh-prompt
fi

export PS1='\[\e[1;33m\][ \u@\H \[\e[0;31m\]| \[\e[1;36m\]\w \[\e[0;31m\]| \[\e[1;32m\] $? \[\e[0;31m\]|\[\e[1;33m\]`__git_ps1` \[\e[0;31m\]| \[\e[01;37m\]`date +"%Y-%m-%d %H:%M:%S"`\[\e[0m\]\[\e[1;33m\] ]\[\e[0m\]\n$ '
EOF"
    }

    # 普通用户
    setup_ps1_for_user "$CURRENT_USER" "$CURRENT_HOME"

    # root
    setup_ps1_for_user "root" "$ROOT_HOME"

    log "Bash PS1 configured for root and $CURRENT_USER"
}


# -------------------------------------------------------------------------------------------------------
# 配置 Terminator
# -------------------------------------------------------------------------------------------------------
configure_terminator_for_user() {
    configure_terminator() {
        log "=== Configuring Terminator ==="

        local user=$1
        local home_dir
        home_dir=$(getent passwd "$user" | cut -d: -f6)

        local config_dir="$home_dir/.config/terminator"
        local config_file="$config_dir/config"

        run "mkdir -p $config_dir"

        # -------------------------
        # 防止重复写
        # -------------------------
        if grep -q "FiraCode Nerd Font 15" "$config_file" 2>/dev/null; then
            log "Terminator already configured for $user, skipping..."
            return
        fi

        # -------------------------
        # 写入配置（关键：'EOF' 防止解析）
        # -------------------------
        run "cat > $config_file << 'EOF'
    [global_config]
    [keybindings]

    [profiles]
      [[default]]
        background_color = \"#1d0303\"
        cursor_color = \"#d9f1f1\"
        font = FiraCode Nerd Font 15
        foreground_color = \"#d9f1f1\"
        scrollback_lines = 50000
        palette = \"#000000:#cd0000:#00cd00:#cdcd00:#5152ec:#cd00cd:#00cdcd:#e5e5e5:#7f7f7f:#ff0000:#00ff00:#ffff00:#5c5cff:#ff00ff:#00ffff:#ffffff\"
        use_system_font = False
        copy_on_selection = True
        background_image = None

    [layouts]
      [[default]]
        [[[child1]]]
          parent = window0
          profile = default
          type = Terminal
        [[[window0]]]
          parent = \"\"
          size = 1330, 1000
          type = Window

    [plugins]
    EOF"

        log "Terminator configured for $user"
    }
    
    configure_terminator "$(whoami)"
    configure_terminator root
}

# -------------------------------------------------------------------------------------------------------
# 安装完成
# -------------------------------------------------------------------------------------------------------
finish() {
    log "========= Setup completed ========="
    log "Please reboot system for best results."
}

# -------------------------------------------------------------------------------------------------------
# 执行入口
# -------------------------------------------------------------------------------------------------------
main() {
    switch_apt_source_auto

    update_system

    install_base_tools
    install_python
    install_debug_tools
    install_network_tools
    install_wifi_tools
    install_kernel_dev
    install_build_system
    install_vmware_tools
    install_optional_tools
    install_nerd_font_firacode
    install_neovim_lazyvim
    install_beyond_compare
    install_zsh_ohmyzsh_all

    configure_bash_ps1

    configure_terminator_for_user

    finish
}


# -------------------------------------------------------------------------------------------------------
# 脚本入口
# -------------------------------------------------------------------------------------------------------
main "$@"
