#!/bin/bash

# Variables globales
KERNEL_VERSION=$(uname -r)
SELECTED_VERSION=""

# Función para detectar el sistema operativo
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        if [[ $ID_LIKE ]]; then
            OS_FAMILY=$ID_LIKE
        else
            OS_FAMILY=$ID
        fi
    else
        echo "No se puede detectar el sistema operativo"
        exit 1
    fi
}

# Función mejorada para verificar dependencias
check_dependency() {
    local dep=$1
    case $OS_FAMILY in
        *debian*)
            dpkg -l | grep -q "^ii.*$dep"
            ;;
        *arch*)
            pacman -Qi "$dep" >/dev/null 2>&1
            ;;
        *fedora*|*rhel*)
            rpm -q "$dep" >/dev/null 2>&1
            ;;
    esac
    return $?
}

# Función para instalar dependencias
install_dependencies() {
    local package_manager
    local install_cmd
    local headers_package="linux-headers-${KERNEL_VERSION}"
    
    case $OS_FAMILY in
        *debian*)
            package_manager="apt"
            install_cmd="apt install -y"
            deps=("build-essential" "$headers_package" "linux-image-${KERNEL_VERSION}-dbg")
            ;;
        *arch*)
            package_manager="pacman"
            install_cmd="pacman -S --noconfirm"
            deps=("base-devel" "linux-headers" "dwarfdump")
            ;;
        *fedora*|*rhel*)
            package_manager="dnf"
            install_cmd="dnf install -y"
            deps=("@development-tools" "kernel-devel" "kernel-debug" "dwarfdump")
            ;;
        *)
            echo "Sistema operativo no soportado"
            exit 1
            ;;
    esac

    # Actualizar repositorios primero
    case $OS_FAMILY in
        *debian*)
            echo "Actualizando repositorios..."
            sudo apt update
            # Habilitar repositorios deb-src si no están habilitados
            if ! grep -q "^deb-src" /etc/apt/sources.list; then
                echo "Habilitando repositorios deb-src..."
                sudo sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list
                sudo apt update
            fi
            ;;
    esac

    # Actualizar repositorios y habilitar repositorios de depuración
    update_debug_repos() {
        # Detectar la distribución específica
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO_ID=$ID
            DISTRO_VERSION=$VERSION_ID
        fi

        case $DISTRO_ID in
            kali)
                echo "Actualizando repositorios para Kali Linux..."
                sudo apt update
                # Habilitar repositorios deb-src si no están habilitados
                if ! grep -q "^deb-src" /etc/apt/sources.list; then
                    echo "Habilitando repositorios deb-src..."
                    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
                    sudo sed -i 's/^# *deb-src/deb-src/' /etc/apt/sources.list
                fi
                # Agregar repositorios debug específicos de Kali
                if ! grep -q "kali-debug" /etc/apt/sources.list; then
                    echo "Agregando repositorios debug de Kali..."
                    echo "deb http://http.kali.org/kali kali-rolling-debug main contrib non-free" | \
                        sudo tee -a /etc/apt/sources.list.d/kali-debug.list
                fi
                sudo apt update
                ;;

            parrot)
                echo "Actualizando repositorios para Parrot OS..."
                sudo apt update
                # Habilitar repositorios deb-src
                if ! grep -q "^deb-src" /etc/apt/sources.list; then
                    echo "Habilitando repositorios deb-src..."
                    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
                    sudo sed -i 's/^# *deb-src/deb-src/' /etc/apt/sources.list
                fi
                # Agregar repositorios debug específicos de Parrot
                if ! grep -q "parrot-debug" /etc/apt/sources.list.d/parrot-debug.list 2>/dev/null; then
                    echo "Agregando repositorios debug de Parrot..."
                    echo "deb http://deb.parrotsec.org/parrot parrot-debug main contrib non-free" | \
                        sudo tee /etc/apt/sources.list.d/parrot-debug.list
                fi
                sudo apt update
                ;;

            ubuntu|debian)
                echo "Actualizando repositorios para ${DISTRO_ID^}..."
                sudo apt update
                # Habilitar repositorios deb-src
                if ! grep -q "^deb-src" /etc/apt/sources.list; then
                    echo "Habilitando repositorios deb-src..."
                    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
                    sudo sed -i 's/^# *deb-src/deb-src/' /etc/apt/sources.list
                fi
                # Configurar repositorios dbgsym
                if [ "$DISTRO_ID" = "ubuntu" ]; then
                    if ! dpkg -l ubuntu-dbgsym-keyring >/dev/null 2>&1; then
                        echo "Instalando llaves para repositorios dbgsym..."
                        sudo apt install -y ubuntu-dbgsym-keyring
                    fi
                    if ! grep -q "ddebs.ubuntu.com" /etc/apt/sources.list.d/ddebs.list 2>/dev/null; then
                        echo "Configurando repositorio dbgsym de Ubuntu..."
                        codename=$(lsb_release -c | cut -f2)
                        echo "deb http://ddebs.ubuntu.com ${codename} main restricted universe multiverse
    deb http://ddebs.ubuntu.com ${codename}-updates main restricted universe multiverse" | \
                            sudo tee /etc/apt/sources.list.d/ddebs.list
                    fi
                elif [ "$DISTRO_ID" = "debian" ]; then
                    if ! grep -q "debian-debug" /etc/apt/sources.list.d/debian-debug.list 2>/dev/null; then
                        echo "Configurando repositorio debug de Debian..."
                        codename=$(lsb_release -c | cut -f2)
                        echo "deb http://debug.mirrors.debian.org/debian-debug/ ${codename}-debug main" | \
                            sudo tee /etc/apt/sources.list.d/debian-debug.list
                    fi
                fi
                sudo apt update
                ;;

            backbox)
                echo "Actualizando repositorios para BackBox..."
                sudo apt update
                # Habilitar repositorios deb-src
                if ! grep -q "^deb-src" /etc/apt/sources.list; then
                    echo "Habilitando repositorios deb-src..."
                    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
                    sudo sed -i 's/^# *deb-src/deb-src/' /etc/apt/sources.list
                fi
                # Agregar repositorios debug específicos de BackBox
                if ! grep -q "backbox-debug" /etc/apt/sources.list.d/backbox-debug.list 2>/dev/null; then
                    echo "Agregando repositorios debug de BackBox..."
                    codename=$(lsb_release -c | cut -f2)
                    echo "deb http://ppa.launchpad.net/backbox/debug/ubuntu ${codename} main" | \
                        sudo tee /etc/apt/sources.list.d/backbox-debug.list
                fi
                sudo apt update
                ;;

            *)
                echo "Distribución no soportada específicamente: $DISTRO_ID"
                echo "Intentando configuración genérica basada en Debian..."
                sudo apt update
                if ! grep -q "^deb-src" /etc/apt/sources.list; then
                    echo "Habilitando repositorios deb-src..."
                    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
                    sudo sed -i 's/^# *deb-src/deb-src/' /etc/apt/sources.list
                    sudo apt update
                fi
                ;;
        esac
    }
}

# Función para seleccionar versión
select_version() {
    echo "Seleccione la versión de Volatility para la que desea crear el mapa:"
    echo "1) Volatility 2"
    echo "2) Volatility 3"
    echo "3) Ambos"
    read -p "Seleccione una opción (1-3): " version_choice
    
    case $version_choice in
        1) SELECTED_VERSION="vol2" ;;
        2) SELECTED_VERSION="vol3" ;;
        3) SELECTED_VERSION="both" ;;
        *) 
            echo "Opción inválida"
            exit 1
            ;;
    esac
}

# Función para compilar el módulo
compile_module() {
    local kernel_src="/lib/modules/${KERNEL_VERSION}/build"
    
    if [ ! -d "$kernel_src" ]; then
        echo "Error: No se encuentra el directorio de construcción del kernel en $kernel_src"
        echo "Asegúrese de que linux-headers-${KERNEL_VERSION} está instalado correctamente"
        exit 1
    fi

    if [ ! -d "tools/linux" ]; then
        echo "Error: No se encuentra el directorio tools/linux"
        exit 1
    fi

    cd tools/linux
    make
    if [ $? -ne 0 ]; then
        echo "Error durante la compilación"
        exit 1
    fi
    cd ../../
}

# Función para localizar el System.map correcto
find_system_map() {
    local possible_locations=(
        "/usr/lib/debug/boot/System.map-$KERNEL_VERSION"
        "/usr/lib/debug/System.map-$KERNEL_VERSION"
    )

    for location in "${possible_locations[@]}"; do
        if [ -f "$location" ]; then
            echo "$location"
            return 0
        fi
    done

    echo "No se pudo encontrar un System.map válido. Asegúrese de que el paquete linux-image-${KERNEL_VERSION}-dbg está instalado correctamente."
    exit 1
}

# Función para preparar archivos Vol2
prepare_files_vol2() {
    local system_map=$(find_system_map)
    
    # Verificar y mover module.dwarf
    if [ ! -f "tools/linux/module.dwarf" ]; then
        echo "Error: No se encuentra module.dwarf"
        exit 1
    fi
    cp tools/linux/module.dwarf ./

    # Crear estructura de directorios y copiar archivos
    mkdir -p temp_vol2/boot
    cp module.dwarf temp_vol2/
    cp "$system_map" temp_vol2/boot/

    # Crear el archivo ZIP
    zip_name="${OS}-kernel-${KERNEL_VERSION}-vol2.zip"
    cd temp_vol2
    zip -r "../$zip_name" ./*
    cd ..
    
    # Limpiar archivos temporales
    rm -rf temp_vol2
    rm module.dwarf
}

# Función para crear perfil Vol3
create_vol3_profile() {
    local vmlinux_path="/usr/lib/debug/boot/vmlinux-${KERNEL_VERSION}"
    local system_map_path="/usr/lib/debug/boot/System.map-${KERNEL_VERSION}"
    
    # Verificar que existe dwarf2json
    if [ ! -f "./dwarf2json" ]; then
        echo "Error: No se encuentra dwarf2json en el directorio actual"
        exit 1
    fi
    
    # Hacer ejecutable dwarf2json si no lo está
    chmod +x ./dwarf2json
    
    # Crear directorio temporal para Vol3
    mkdir -p temp_vol3
    
    echo "Generando archivos JSON para Volatility 3..."
    
    ./dwarf2json linux --elf "$vmlinux_path" > \
        "temp_vol3/linux-image-${KERNEL_VERSION}-dbg_${KERNEL_VERSION}_amd64.json"
    
    ./dwarf2json linux --elf "$vmlinux_path" --system-map "$system_map_path" > \
        "temp_vol3/linux-image-${KERNEL_VERSION}-dbg_${KERNEL_VERSION}_amd64-SystemMap.json"
    
    # Crear ZIP para Vol3
    local zip_name="${OS}-kernel-${KERNEL_VERSION}-vol3.zip"
    cd temp_vol3
    zip -r "../$zip_name" ./*
    cd ..
    
    # Limpiar archivos temporales
    rm -rf temp_vol3
}

# Función para mostrar instrucciones
show_instructions() {
    echo -e "\n=== Instrucciones de instalación ==="
    if [[ $SELECTED_VERSION == "vol2" || $SELECTED_VERSION == "both" ]]; then
        echo "Para Volatility 2:"
        echo "- Copie el archivo ${OS}-kernel-${KERNEL_VERSION}-vol2.zip a la carpeta /usr/lib/volatility/plugins/overlays/linux/"
        echo "- Descomprima el archivo en esa ubicación"
    fi
    
    if [[ $SELECTED_VERSION == "vol3" || $SELECTED_VERSION == "both" ]]; then
        echo -e "\nPara Volatility 3:"
        echo "- Copie los archivos JSON del archivo ${OS}-kernel-${KERNEL_VERSION}-vol3.zip a la carpeta /usr/local/lib/python3.x/dist-packages/volatility3/symbols/linux/"
        echo "  (Reemplace 'x' con su versión de Python)"
    fi
}

# Función principal
main() {
    detect_os
    echo "Sistema detectado: $OS (familia: $OS_FAMILY)"
    install_dependencies
    select_version
    
    case $SELECTED_VERSION in
        "vol2")
            compile_module
            prepare_files_vol2
            ;;
        "vol3")
            create_vol3_profile
            ;;
        "both")
            compile_module
            prepare_files_vol2
            create_vol3_profile
            ;;
    esac
    
    show_instructions
    echo "Proceso completado con éxito"
}

# Ejecutar el script
main
