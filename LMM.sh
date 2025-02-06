#!/bin/bash

# Variables globales
KERNEL_VERSION=$(uname -r)
SELECTED_VERSION=""

if [ "$(id -u)" -ne 0 ]; then
    echo "Advertencia: Este script requiere permisos de administrador."
    echo "Por favor, ejecute el script como root o usando sudo."
    exit 1
fi

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
            # Verificar si el paquete está instalado en sistemas basados en Debian
            dpkg -l | grep -q "^ii.*$dep"
            ;;
        *)
            echo "Sistema operativo no soportado para verificación de dependencias"
            return 1
            ;;
    esac
    return $?
}

# Función para instalar dependencias
install_dependencies() {
    local package_manager
    local install_cmd
    local headers_package="linux-headers-${KERNEL_VERSION}"

    # Usar ID de /etc/os-release para detectar correctamente Ubuntu o Debian
    . /etc/os-release
    DISTRO_ID=$ID

    case $DISTRO_ID in
        debian)
            package_manager="apt"
            # Si es Debian, instalar las dependencias estándar
            deps=("build-essential" "$headers_package" "linux-image-${KERNEL_VERSION}-dbg" "make" "dwarfdump" "zip")
            install_cmd="sudo apt install -y ${deps[@]}"
            ;;

        ubuntu)
            package_manager="apt"
            # Si es Ubuntu, instalar dependencias y configurar dbgsym
            deps=("build-essential" "$headers_package" "linux-image-${KERNEL_VERSION}" "gcc" "make" "dwarfdump" "zip")
            install_cmd="sudo apt install -y ${deps[@]}"
            # Configurar repositorios dbgsym si es Ubuntu
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
            ;;
        *)
            echo "Sistema operativo no soportado"
            exit 1
            ;;
    esac

    # Instalar las dependencias
    echo "Instalando dependencias para $DISTRO_ID..."
    eval "$install_cmd"
    if [ $? -ne 0 ]; then
        echo "Error durante la instalación de dependencias"
        exit 1
    fi
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
    local kernel_src
    local build_dir="build"
    
    # Detectar el sistema operativo para ajustar la ruta del kernel
    case $OS_FAMILY in
        *debian*)
            # En sistemas Debian/Ubuntu
            kernel_src="/lib/modules/${KERNEL_VERSION}/build"
            ;;
        *)
            echo "Sistema operativo no soportado para la compilación del módulo"
            exit 1
            ;;
    esac

    # Verificar si el directorio de construcción del kernel existe
    if [ ! -d "$kernel_src" ]; then
        echo "Error: No se encuentra el directorio de construcción del kernel en $kernel_src"
        echo "Asegúrese de que linux-headers-${KERNEL_VERSION} está instalado correctamente"
        exit 1
    fi

    # Verificar si el directorio tools/linux existe
    if [ ! -d "tools/linux" ]; then
        echo "Error: No se encuentra el directorio tools/linux"
        exit 1
    fi

    # Cambiar al directorio de herramientas y compilar
    cd tools/linux
    make
    if [ $? -ne 0 ]; then
        echo "Error durante la compilación. Verifique los errores anteriores."
        exit 1
    fi
    cd ../../
}


# Función para localizar el System.map correcto
find_system_map() {
    local possible_locations=(
        "/usr/lib/debug/boot/System.map-$KERNEL_VERSION"
        "/usr/lib/debug/System.map-$KERNEL_VERSION"
        "/boot/System.map-$KERNEL_VERSION"
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

# Función para crear perfil Vol3 dependiendo del sistema operativo
create_vol3_profile() {
    local vmlinux_path=""
    local system_map_path=""
    
    # Verificar sistema operativo
    . /etc/os-release
    DISTRO_ID=$ID
    DISTRO_VERSION=$VERSION_ID

    case $DISTRO_ID in
        debian)
            vmlinux_path="/usr/lib/debug/boot/vmlinux-${KERNEL_VERSION}"
            system_map_path="/usr/lib/debug/boot/System.map-${KERNEL_VERSION}"
            ;;
        ubuntu)
            # Para Ubuntu, configuramos los repositorios de depuración
            echo "Configurando repositorios ddebs para Ubuntu..."
            echo "deb http://ddebs.ubuntu.com $(lsb_release -cs) main restricted universe multiverse" | \
                sudo tee -a /etc/apt/sources.list.d/ddebs.list
            echo "deb http://ddebs.ubuntu.com $(lsb_release -cs)-updates main restricted universe multiverse" | \
                sudo tee -a /etc/apt/sources.list.d/ddebs.list
            echo "deb http://ddebs.ubuntu.com $(lsb_release -cs)-proposed main restricted universe multiverse" | \
                sudo tee -a /etc/apt/sources.list.d/ddebs.list
            
            # Instalar el paquete de llaves para los repositorios ddebs
            sudo apt install -y ubuntu-dbgsym-keyring
            
            # Importar la clave pública de los repositorios
            sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F2EDC64DC5AEE1F6B9C621F0C8CAB6595FDFF622
            
            # Actualizar los repositorios
            sudo apt-get update
            
            # Instalar el paquete de depuración para la versión del kernel actual
            sudo apt install -y linux-image-${KERNEL_VERSION}-dbgsym

            vmlinux_path="/usr/lib/debug/boot/vmlinuz-${KERNEL_VERSION}"
            system_map_path="/usr/lib/debug/boot/System.map-${KERNEL_VERSION}"
            ;;
        *debian*|*ubuntu*)
            vmlinux_path="/usr/lib/debug/boot/vmlinux-${KERNEL_VERSION}"
            system_map_path="/usr/lib/debug/boot/System.map-${KERNEL_VERSION}"
            ;;
        *)
            echo "Sistema operativo no soportado para la creación del perfil Vol3."
            exit 1
            ;;
    esac
    
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
    
    # Ejecutar dwarf2json para generar los archivos JSON
    ./dwarf2json linux --elf "$vmlinux_path" > \
        "temp_vol3/linux-image-${KERNEL_VERSION}-dbg_${KERNEL_VERSION}_amd64.json"
    
    ./dwarf2json linux --elf "$vmlinux_path" --system-map "$system_map_path" > \
        "temp_vol3/linux-image-${KERNEL_VERSION}-dbg_${KERNEL_VERSION}_amd64-SystemMap.json"
    
    # Crear ZIP para Vol3
    local zip_name="${DISTRO_ID}-kernel-${KERNEL_VERSION}-vol3.zip"
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
