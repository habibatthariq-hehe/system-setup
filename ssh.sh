echo "==== SSH-KEYGEN STARTED ===="
ssh-keygen
sleep 3
echo "==== COPY SSH KEY TO SERVER ===="
ssh-copy-id -i ~/.ssh/id_ed25519.pub debian@192.168.1.65
echo "==== PROCESS COMPLETE ===="