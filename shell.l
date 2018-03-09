
/*
 *
 * CS-252 Fall 2017
 * shell.l: lexical analyzer for shell
 * You have to extend it.
 *
 */

%{

#include <cstring>
#include "y.tab.hh"
#include <string.h>
#include <stdio.h>
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pwd.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <assert.h>
#include <sys/prctl.h>
#include "command.hh"

extern "C" char* read_line();

////////////  Start added code ///////////
//char * read_line();

int mygetc(FILE * f) {
    static char *p;
    char ch;
    
    if (!isatty(0)) {
        // stdin is not a tty. Call real getc
        return getc(f);
    }
    
    // stdin is a tty. Call our read_line.
    
    if (p==NULL || *p == 0) {
        char * s = read_line();
        p = s;
    }
    
    ch = *p;
    p++;
    
    return ch;
}

#undef getc
#define getc(f) mygetc(f)

/////////// End added code ///////////



int MAXBUFFERSIZE = 1024;
static  void yyunput (int c,char *buf_ptr  );

void escapeChars();
void quotesChars();

int subshell();


//extern char* read_line();
extern char* shelldir;




void myunputc(int c) {
  unput(c);
}




%}
/* Source Implementation -  using Lex Buffers available, open the file stream, read into buffers
 and then close the buffer */

%x incl

%%
"source"      BEGIN(incl);

<incl>[ \t]*      /* remove white space */
<incl>[^ \t\n]+   { /* read the file name */
    yyin = fopen( yytext, "r" ); /* open file */
    
    if ( ! yyin ) {
        perror("File open error\n");
    }
    
    yypush_buffer_state(yy_create_buffer( yyin, YY_BUF_SIZE ));
    BEGIN(INITIAL);
}

<<EOF>> {
    yypop_buffer_state();
    if ( !YY_CURRENT_BUFFER ) {
        yyterminate();
    }
}
\n {
    return NEWLINE;
}


[ \t] {
  /* Discard spaces and tabs */
}


"&" {
    return AND;
}


">&" {
    return GREATAND;
}

">>" {
    return DOUBLEGREAT;
}

">>&" {
    return DOUBLEGREATAND;
}

"<" {
    return LESS;
}

"|" {
    return PIPE;
}

">" {
  return GREAT;
}
"2>" {
    return TWOGREAT;
}




\"[^\t\n\"]*\"  {



quotesChars();
return WORD;

}

[^ \t\n]*(\\[^\s])[^ \t\n]*  {
    /* Assume that file names have only alpha chars */
    escapeChars();
    //printf("understood");
    
    
    yylval.string_val = strdup(yytext);
    return WORD;
}

[`]([^"']|a-zA-Z\\.)*[`] {
//subshell
subshell();

}

[^ ^\\&<>|\t\n][^ ^\\&<>|\t\n]*	{
   
    /* Assume that file names have only alpha chars */
    yylval.string_val = strdup(yytext);
   
    return WORD;
}









%%


void escapeChars()
{
    int len = strlen(yytext) +1 ;
    char* temp = (char*)malloc(len);
    int escape = 0;
    int var1 = 0;
    int var2 = 0;
    while(var2 < len - 1)
    {
        if(yytext[var2] == '\\' && escape == 0)
        {
            escape = 1;
        }
        else if(escape == 1)
        {
            temp[var1] = yytext[var2];
            var1++;
            escape = 0;
        }
        else
        {
            temp[var1] = yytext[var2];
            var1++;
        }
        var2++;
    } 
    temp[var1] = '\0';
    strcpy(yytext, temp);
    free(temp);
}

void quotesChars() {
    yylval.string_val = strdup(yytext+1);
    if (yylval.string_val[yyleng-2] == '"')
    yylval.string_val[yyleng-2] = 0;
    
}

/* subshell function that gets called when "source" keyword is recognized*/
/*	Read the text from command, pipe to the subshell process			*/
/*	fork and exceute shell, read back from pipe and put back text		*/
/*																		*/
int subshell() {
    /* read text supplied*/
    char* temp = strdup(yytext+1);
    char* yyTemp = strdup(temp);
    int len = strlen(yyTemp)-1;
    yyTemp[len] = '\n';
    
    
    char cArr[2048];
    /* pipes to link input/output between */
    /* subshell and main process */
    int pipe_in[2];
    int pipe_out[2];
    if (pipe(pipe_in) < 0 || pipe(pipe_out) < 0) {
        perror("subshell - pipe error");
        free(yyTemp);
        return 1;
    }
    int fdIn, fdOut;
    
    fdIn  = dup(0);
    fdOut =  dup(1);
    
    dup2(pipe_in[1], 1);
    close(pipe_in[1]);
    
    dup2(pipe_out[0], 0);
    close(pipe_out[0]);
    
    pid_t pid;
    
    if((pid = fork()) <0){
        perror("fork");
        _exit(0);
    }
    else if(pid ==0){
        dup2(pipe_in[0], 0);
        close(pipe_in[0]);
        dup2(pipe_out[1], 1);
        close(pipe_out[1]);
        
        execvp("/proc/self/exe",NULL);
        perror("subshell");
        
        _exit(1);
    }
    else{
        /* write the command text */
        int i =0;
        while(i<len+1 && write(1,yyTemp+i,1)){
            i++;
        }
        
        dup2(fdOut,1);
        close(fdOut);
        close(pipe_out[1]);
        
        char* rc = cArr;
        /* read back from the subshell */
        for(char ch=0; read(0,&ch,1);rc++){
            if(ch!='\n'){
                *rc = ch;
            }
            else {
                *rc = ' ';
            }
        }
        /* now put back the text */
        for(rc--;rc>=cArr;rc--){
            unput(*rc);
        }
        
        dup2(fdIn,0);
        close(fdOut);
        
    }
    
    // Wait for all processes 
    waitpid(pid,NULL,0);
}



