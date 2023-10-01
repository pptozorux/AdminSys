from os import path, mkdir
from sys import argv
from shutil import copyfile
from subprocess import run
from threading import Thread
from concurrent.futures import ThreadPoolExecutor
from queue import Queue


# ANSI escape codes for text colors
RED = '\033[91m'  # for fatal errors
GREEN = '\033[92m'  # for inputs
YELLOW = '\033[93m'  # for warnings
BLUE = '\033[94m'  # for info
RESET = '\033[0m'  # Reset to the default color

lab_name = input(GREEN + "Nom du lab : " + RESET)

class VM:
    def __init__(self, name, ram, ip_address, vlan, tap):
        self.name = name
        self.ram = ram
        self.ip_address = ip_address
        self.img_path = f"{name}.qcow2"
        self.vlan = vlan
        self.tap = tap

    def start(self):
        print(BLUE + "Starting VM " + self.name + RESET)
        print(BLUE + self.img_path + RESET)
        run(["bash", path.expanduser("~/vm/scripts/ovs-startup.sh"), path.expanduser(f"~/vm/{lab_name}/{self.img_path}"), self.ram, self.tap])

    def __str__(self):
        return self.name

def f_thread(vms, type):

    def copy_img(vm : VM) -> None :
        if not path.exists(path.join(dir, vm.img_path)):
            print(YELLOW + "Image " + vm.img_path + " not found" + RESET)
            print(BLUE + "Copying image " + vm.img_path + RESET)
            copyfile(path.expanduser(f"{MASTERS.get(type,argv[1])}"), path.join(dir, vm.img_path))
    
    with ThreadPoolExecutor(max_workers=4) as executor:
        executor.map(copy_img, vms)
        executor.map(lambda vm : run(["sudo", "ovs-vsctl", "set", "port",f"tap{vm.tap}", f"tag={vm.vlan}"]), vms) # config taps port vlan
        executor.map(lambda vm : vm.start(), vms)

if __name__ == "__main__":
    if len(argv) < 2:
        print(RED + "Usage : " + argv[0] + " <client-master> [<server-master>] [options]" + RESET)
        exit(1)
    elif len(argv) == 2:
        MASTERS = {"*": argv[1]}
    elif len(argv) >= 3:
        MASTERS = {"client": argv[1], "server": argv[2]}

    if "--same-vlan" in argv:
        vlan = input(GREEN + "Vlan : " + RESET)

    if "--set-tap" in argv :
        deb = input(GREEN +"Entrez le début de l'intervalle de tap affecté : " + RESET)
        fin = input(GREEN + "Entrez la fin de l'intervalle tap : " + RESET)
        q = Queue()
        for i in range(int(deb),int(fin)+1) :
            q.put(i)
        print(BLUE + "Q length : " + str(q.qsize()) + RESET)
        

    n_client = input(GREEN + "Nombre de clients : " + RESET)
    n_server = input(GREEN + "Nombre de serveurs : " + RESET)

    clients = []
    servers = []

    # does the lab exist ?
    dir = path.expanduser(f"~/vm/{lab_name}")
    # if not, create it
    if not path.exists(dir):
        print(YELLOW + "Folder " + dir + " not found" + RESET)
        print(BLUE + "Creating folder " + dir + RESET)
        mkdir(dir)

    print(BLUE + "Création des VM..." + RESET)

    if not "--same-vlan" in argv and not "--set-tap" in argv: 
        print(BLUE + "Pas d'options" + RESET)
        for i in range(int(n_client)):
            print(BLUE + "Création du client "  + str(i) + RESET)
            clients.append(VM("client" + str(i), input("ram: "), input("ip_address: "), input("vlan: "), input("tap: ")))

        for i in range(int(n_server)):
            print("Création du serveur " + str(i))
            servers.append(VM("server" + str(i), input("ram: "), input("ip_address: "), input("vlan: "), input("tap: ")))
    elif "--same-vlan" in argv and not "--set-tap" in argv :
        print(BLUE + "Options : --same-vlan " + RESET)
        for i in range(int(n_client)):
            print(BLUE + "Création du client "  + str(i) + RESET)
            clients.append(VM("client" + str(i), input("ram: "), input("ip_address: "), int(vlan), input("tap: ")))
        for i in range(int(n_server)):
            print("Création du serveur " + str(i))
            servers.append(VM("server" + str(i), input("ram: "), input("ip_address: "), int(vlan), input("tap: ")))
    elif "--set-tap" in argv and not "--same-vlan" in argv :
        print(BLUE + "Options : --set-tap" + RESET)
        for i in range(int(n_client)) : 
            if not q.empty() : 
                print(BLUE + "Création du client "  + str(i) + RESET)
                clients.append(VM("client" + str(i), input("ram: "), input("ip_address: "), input("vlan: "), str(q.get())))
            else : 
                print(RED + "Erreur : La file de tap est vide\n"
                      + "Vous n'avez pas mis une fin assez grande")

        for i in range(int(n_server)) : 
            if not q.empty() : 
                print(BLUE + "Création du server "  + str(i) + RESET)
                servers.append(VM("server" + str(i), input("ram: "), input("ip_address: "), input("vlan: "), str(q.get())))
            else : 
                print(RED + "Erreur : La file de tap est vide\n"
                      + "Vous n'avez pas mis une fin assez grande")        
    elif "--set-tap" in argv and "--same-vlan" in argv :
        print(BLUE + "Options : --set-tap --same-vlan" + RESET)
        for i in range(int(n_client)) : 
            if not q.empty() : 
                print(BLUE + "Création du client "  + str(i) + RESET)
                clients.append(VM("client" + str(i), input("ram: "), input("ip_address: "), int(vlan), str(q.get())))
            else : 
                print(RED + "Erreur : La file de tap est vide\n"
                      + "Vous n'avez pas mis une fin assez grande")

        for i in range(int(n_server)) : 
            if not q.empty() : 
                print(BLUE + "Création du server "  + str(i) + RESET)
                servers.append(VM("server" + str(i), input("ram: "), input("ip_address: "), int(vlan), str(q.get())))
            else : 
                print(RED + "Erreur : La file de tap est vide\n"
                      + "Vous n'avez pas mis une fin assez grande")
    else :

        print(RED + "Usage : " + argv[0] + " <client-master> [<server-master>] [options]" + RESET)
        exit(1)


    threads = [Thread(target=f_thread, args=(clients, "client")),
               Thread(target=f_thread, args=(servers, "server"))]

    print(BLUE + "Démarrage des VM..." + RESET)

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()
    
    exit(0)