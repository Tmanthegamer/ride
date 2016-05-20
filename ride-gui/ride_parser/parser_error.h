#ifndef ERROR_OBJECT_H
#define ERROR_OBJECT_H

/*
 * @brief      Type define of an error object
 * @details    This object indicates an error message that can be returned to
 *             the GUI.
 */
typedef struct error_object
{
    char *message;
    int message_length;
    int line_number;
    int column_start;
    int num_characters;
} Error;
#endif  // ERROR_OBJECT_H
