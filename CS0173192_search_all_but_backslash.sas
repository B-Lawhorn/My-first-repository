/* only use this step if you have created work datasets  */
/* from previous TS provided code */

options noserror noquotelenmax;

ods listing close;
proc datasets lib=work mt=data kill nolist; run;
quit;
ods listing close;
%let htmlname=bari;
%let htmlpath=/tmp/;
%let directory=/Public;

/* Get the folder id for the directory in question */
filename first temp;
proc http method="get"
url="https://sas-folders/folders/folders/@item?path=&directory"
OAUTH_BEARER=SAS_SERVICES
out=first;
debug level=1;
run;

libname test json fileref=first;

data _null_;
 set test.root;
 call symputx("folderid",id);
run;

/* %put &folderid; */
/* Search the folder recursively for files with special characters in the name */
filename second temp;
proc http method="get"
url=%tslit(https://sas-folders/folders/folders/&folderid./members?filter=or(contains(name,%27?%27),contains(name,%27<%27),contains(name,%27>%27),contains(name,%27|%27),contains(name,%27:%27),contains(name,%27*%27),contains(name,%27/%27),contains(name,%27%quote(%")%27))%nrstr(&recursive)=true&limit=100)
OAUTH_BEARER=SAS_SERVICES
out=second;
debug level=1;
run;

libname test2 json fileref=second;
/* TS added logic to check the number of variables in TEST2.ITEMS
   if more than 2, we go through all the steps. */

  %let dsid = %sysfunc(open(test2.items));

   %if &dsid %then %do;
      %let nvars=%sysfunc(attrn(&dsid,nvars));
      %let rc = %sysfunc(close(&dsid));
   %end;

  %if &nvars gt 2 %then %do;
  
/* We'll need info from two tables, ITEMS to grab the names  */
/* and ITEMS_LINKS to grab the directory / ancestors */
data badones;
 set test2.items(keep=ordinal_items	name parentFolderUri uri );
 rename name=badname;
run;

data badones_rename;
 set test2.items_links;
 where rel ="ancestors";
run;

/* Let's go find the folders the files   */
 %macro findfolders(value,n);

filename third temp;
proc http method="get"
url="https://sas-folders&value"
OAUTH_BEARER=SAS_SERVICES
out=third;
debug level=1;
run;      
  
libname test json fileref=third;

/* Create a unique counter so we can transpose the directories later */
data test&n;
length name $ 256;
set test.ancestors;
n=&n;
run;

proc append base=folder data=test&n;
run;

filename third clear;

   %mend;

   proc sort data=badones_rename;
     by ordinal_items;
   run;

   data _null_;
     set badones_rename(where=(rel="ancestors"));
     by ordinal_items;
     if first.ordinal_items then 
       call execute('%findfolders('||uri||','||_n_||')');
    
   run;

/* We need to reshape the folders table and merge it with the  */
/* table that contains the filenames */

proc sort data=folder(keep=n ordinal_ancestors id	name) out=sorted;
  by n descending ordinal_ancestors;
run;

proc transpose data=sorted out=out2(drop=_name_);
by n;
var name;
run;

data out3;
set out2;
rename n=ordinal_items;
folder=catx('\',of col:);
drop col:;
run;


data combine(drop=ordinal_items);
merge badones(keep=ordinal_items badname) out3;
by ordinal_items;
run;

ods html file="&htmlname..html" path="&htmlpath";
proc print data=combine label;
title "files with restricted characters in the names and their folders";
var folder badname;
label badname="Name" 
folder="Folder"; 
run;

 %macro rename(flow,newname);

filename rename temp;
proc http 
method="put" 
in=%unquote(%str(%'){"name":"&newname"}%str(%'))
url="https://sas-data-flows&flow"
OAUTH_BEARER=SAS_SERVICES
out=rename;
debug level=1;
headers 'If-Match'='*' 
 'Accept'='application/json, application/vnd.sas.data.flow+json, application/vnd.sas.summary+json, application/vnd.sas.error+json' 
 'Content-Type'='application/json' ;
run;

   %mend;

data badones; 
 length newname $ 256;
 set test2.items;
 newname=compress(translate(name,"___________",'\?<>|:*"/()'));
 put name $256.;
 put newname $256.;
run;

   proc sort data=badones;
     by uri;
   run;

/* call the macro for each unique flow */
	 
   data _null_;
     set badones;
     by uri;
     if first.uri then;
/*   call execute('%rename('||uri||','||newname||')'); */
       call execute('%rename('||uri||',%str('||strip(newname)||'))');
   run;



/* TS added: there is a %PUT statement that will resolve in the log 
   with information about the directory. If you search for Yay in the 
   log and see it twice, no files with forward slashes were found */
   
%end;

%else %do;

%put **Yay! No files with problematic characters were found in &directory. **;

%end;




