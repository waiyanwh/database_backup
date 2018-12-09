#!/bin/bash

# Auto backup script
####### Start of Config ########

# Encrypt flag
ENCRYPTFLAG=true

# The password used to encrypt the backup
# To decrypt backups made by this script, run the following command:
# openssl enc -aes256 -in [encrypted backup] -out decrypted_backup.tgz -pass pass:[backup password] -d -md sha1
BACKUPPASS=""

# Directory to store backups
LOCALDIR="" # something like /home/user/backup

# Temporary directorty used during backup creation
TEMPDIR="" # something like /home/user/temp

# File to log the outcome of backups
LOGFILE="" # /home/user/backup/backup.log

# OPTIONAL: If you want backup MySQL database, enter the MySQL root password below
MYSQL_USER="" # username
MYSQL_ROOT_PASSWORD="" # Password
MYSQL_HOST="" # hostname

# Below is a list of MySQL database name that will be backed up
# If you want backup ALL databases, leave it blank.
MYSQL_DATABASE_NAME[0]="" # databases name you want to backup

# Below is a list of files and directories that will be backed up in the tar backup
BACKUP[0]=""

# Number of days to store daily local backups (default 7 days)
LOCALAGEDAILIES="7"

# Date & Time
BACKUPDATE=$(date +%Y%m%d%H%M%S)
# Backup file name
TARFILE="${LOCALDIR}""$(hostname)"_"${BACKUPDATE}".tgz
# Encrypted backup file name
ENC_TARFILE="${TARFILE}.enc"
# Backup MySQL dump file name
SQLFILE="${TEMPDIR}mysql_${BACKUPDATE}.sql"

check_commands() {
    # This section checks for all of the binaries used in the backup
    BINARIES=( cd echo openssl mysql mysqldump rm tar )

    # Iterate over the list of binaries, and if one isn't found, abort
    for BINARY in "${BINARIES[@]}"; do
        if [ ! "$(command -v "$BINARY")" ]; then
            echo -e "\e[91m[-]\e[0m$BINARY is not installed. Install it and try again"
            exit 1
        fi
    done

    # check gdrive command
    GDRIVE_COMMAND=false
    if [ "$(command -v "gdrive")" ]; then
        GDRIVE_COMMAND=true
    fi
}

# Backup MySQL databases
mysql_backup() {
    if [ -z ${MYSQL_ROOT_PASSWORD} ]; then
        echo -e "\e[91m[-]\e[0mMySQL root password not set, MySQL backup skipped"
    else
        echo -e "\e[93m[*]\e[0m MySQL dump start"
        mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_ROOT_PASSWORD}" 2>/dev/null <<EOF
exit
EOF
        if [ $? -ne 0 ]; then
            echo -e "\e[91m[-]\e[0mMySQL root password is incorrect. Please check it and try again"
            exit 1    
        fi

        if [ "${MYSQL_DATABASE_NAME[*]}" == "" ]; then
            mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_ROOT_PASSWORD}" --all-databases > "${SQLFILE}" 2>/dev/null
            if [ $? -ne 0 ]; then
                echo -e "\e[91m[-]\e[0mMySQL all databases backup failed"
                exit 1
            fi
            echo -e "\e[93m[*]\e[0m MySQL all databases dump file name: ${SQLFILE}"
            #Add MySQL backup dump file to BACKUP list
            BACKUP=(${BACKUP[*]} ${SQLFILE})
        else
            for db in ${MYSQL_DATABASE_NAME[*]}
            do
                unset DBFILE
                DBFILE="${TEMPDIR}${db}_${BACKUPDATE}.sql"
                mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_ROOT_PASSWORD}" ${db} > "${DBFILE}" 2>/dev/null
                if [ $? -ne 0 ]; then
                    echo -e "\e[91m[-]\e[0mMySQL database name [${db}] backup failed, please check database name is correct and try again"
                    exit 1
                fi
                echo -e "\e[93m[*]\e[0m MySQL database name [${db}] dump file name: ${DBFILE}"
                # Add MySQL backup dump file to BACKUP list
                BACKUP=(${BACKUP[*]} ${DBFILE})
            done
        fi
        echo -e "\e[92m[+]\e[0m MySQL dump completed"
    fi
}


start_backup() {
    [ "${BACKUP[*]}" == "" ] && echo -e "\e[91m[-]\e[0m Error: You must to modify the [$(basename $0)] config before run it!" && exit 1

    echo -e "\e[93m[*]\e[0m Tar backup file start"
    tar -zcPf ${TARFILE} ${BACKUP[*]}
    if [ $? -gt 1 ]; then
        echo -e "\e[91m[-]\e[0m Tar backup file failed"
        exit 1
    fi
    echo -e "\e[92m[+]\e[0m Tar backup file completed"

    # Encrypt tar file
    if ${ENCRYPTFLG}; then
        echo -e "\e[93m[*]\e[0m Encrypt backup file start"
        openssl enc -aes256 -in "${TARFILE}" -out "${ENC_TARFILE}" -pass pass:"${BACKUPPASS}" -md sha1
        echo -e "\e[92m[+]\e[0m Encrypt backup file completed"

        # Delete unencrypted tar
        echo -e "\e[93m[*]\e[0m Delete unencrypted tar file: ${TARFILE}"
        rm -f ${TARFILE}
    fi

    # Delete MySQL temporary dump file
    for sql in `ls ${TEMPDIR}*.sql`
    do
        echo -e "\e[93m[*]\e[0m Delete MySQL temporary dump file: ${sql}"
        rm -f ${sql}
    done

    if ${ENCRYPTFLG}; then
        OUT_FILE="${ENC_TARFILE}"
    else
        OUT_FILE="${TARFILE}"
    fi
    echo -e "\e[93m[*]\e[0m File name: ${OUT_FILE}"
}

gdrive_upload() {
    if ${GDRIVE_COMMAND}; then
        echo -e "\e[93m[*]\e[0m Tranferring backup file to Google Drive"
        gdrive upload --no-progress ${OUT_FILE} >> ${LOGFILE}
        if [ $? -ne 0 ]; then
            echo -e "\e[91m[-]\e[0mError: Tranferring backup file to Google Drive failed"
            exit 1
        fi
        echo -e "\e[92m[+]\e[0m Tranferring backup file to Google Drive completed"
    fi
}

# Main progress
STARTTIME=$(date +%s)
# Check if the backup folders exist and are writeable
if [ ! -d "${LOCALDIR}" ]; then
    mkdir -p ${LOCALDIR}
fi
if [ ! -d "${TEMPDIR}" ]; then
    mkdir -p ${TEMPDIR}
fi

echo -e "\e[93m[*]\e[0m Backup progress start"
check_commands
mysql_backup
start_backup
echo -e "\e[92m[+]\e[0m Backup progress complete"

echo -e "\e[93m[*]\e[0m Upload progress start"
gdrive_upload
echo -e "\e[92m[+]\e[0m Uplode progress complete"

ENDTIME=$(date +%s)
DURATION=$((ENDTIME - STARTTIME))
echo -e "\e[92m[+]\e[0m All done"
echo -e "\e[92m[+]\e[0m Backup and transfer completed in ${DURATION} seconds"

