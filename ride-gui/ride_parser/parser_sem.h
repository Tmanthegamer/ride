#ifndef PARSER_SEM_H
#define PARSER_SEM_H

#include <semaphore.h>
#include "parser_error.h"

#define SEM_CODE        		"/codesem"
#define SHARED_CODE     		"/code"

#define SEM_ERROR       		"/errsem"
#define SHARED_ERROR    		"/error"
#define SHARED_NUMBER_ERROR		"/error_num"

/**
 * @brief      GUI parse request struct
 */
struct semaphore_request
{
    sem_t   *sem;
    int     fd;     // fd is the start position of content in the shared memory block
    char    *content;
};

/**
 * @brief      Parser response struct
 */
struct semaphore_response
{
    sem_t   *sem;
    int     fd;     // fd is the start position of content in the shared memory block
    int     errNumber;
    Error   **content;
};

extern struct semaphore_request sem_doc;
extern struct semaphore_response sem_error;

#endif //PARSER_SEM_H
