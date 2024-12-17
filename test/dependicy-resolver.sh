
#lsmod | grep -m1 "\b$live_modules\b" | awk '{print $4}' | sed 's/,/ /g' 
resolve_modules="macsmc"

echo $resolve_modules

resolve_modules=$(lsmod | grep -m1 "\b$resolve_modules\b" | awk '{print $4}' | tr ',' " ")

while [[ -n "$resolve_modules" ]]; do
    echo "$resolve_modules"
    for item in $resolve_modules; do
        resolve_modules=$(lsmod | grep -m1 "\b$item\b" | awk '{print $4}' | tr ',' " ")
        echo $resolve_modules
        #break
    done
done