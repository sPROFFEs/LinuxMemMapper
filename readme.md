
# Linux Memory Mapper (LMM)

🔍 A Bash script utility to create volatility 2 & 3 memory maps for the executing system.

> Volatility 2 & 3 mapping working on some Debian based distros

> Volatility 2 & 3 mapping working on Ubuntu based distros

> Working on any other distros... please be patient


![Bash](https://img.shields.io/badge/-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/-Linux-FCC624?logo=linux&logoColor=black)

## Description

Linux Memory Mapper (LMM) is an automated tool that provides an easy way to create memory maps for the executing system kernel.

Perfect for easly and automated execution.

## Installation

1. Clone the repository:

```bash
git clone https://github.com/sPROFFEs/LinuxMemMapper.git
```

2. Navigate to the directory and allow execution:

```bash
cd LinuxMemMapper
chmod +x LLM.sh
```

3. Check dependencies: 

Even if you dont need to worry about kernel headers, built-essentials or dbg-images, the scripts needs dwarf2json binary and volatility 2 linux tools.

This are provided here but not maintained so you might need check for updates.

If you do so, make sure to follow the file structure keeps the same as this repository or if you want, modify the script. 

4. Execute 

```bash
./LLM.sh
```


# ⚠️ Important Considerations:

Operations require root privileges

It would generate modifications on the system, do not use on evidence machines. 

Use with caution on production systems

License
This project is currently unlicensed. For usage rights, check oficial Volatility repositories.

Disclaimer: Use this tool responsibly and only on systems you have permission to inspect. The maintainers are not responsible for any misuse or damage caused by this utility.
