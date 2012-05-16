#include <uquad_aux_math.h>
#include <path_planner.h>
#include <control.h>
#include <stdlib.h>

int main(){
    int retval;
    uquad_mat_t *A = NULL;
    uquad_mat_t *B = NULL;
    uquad_mat_t *Q = NULL;
    uquad_mat_t *R = NULL;
    uquad_mat_t *phi = NULL;
    uquad_mat_t *gamma = NULL;
    uquad_mat_t *K =NULL;
    FILE *matrix = NULL;

    matrix = fopen("A","r");
    if(matrix == NULL)
    {
	err_log_stderr("fopen(A)");
	cleanup_if(ERROR_IO);
    }
    A = uquad_mat_alloc(12,12);
    retval = uquad_mat_load(A, matrix);
    cleanup_if(retval);

    matrix = fopen("B","r");
    if(matrix == NULL)
    {
	err_log_stderr("fopen(B)");
	cleanup_if(ERROR_IO);
    }
    B = uquad_mat_alloc(12,4);
    retval = uquad_mat_load(B,matrix);
    cleanup_if(retval);	
    
    matrix = fopen("Q","r"); 
    if(matrix == NULL)
    {
	err_log_stderr("fopen(Q)");
	cleanup_if(ERROR_IO);
    }
    Q = uquad_mat_alloc(12,12);
    retval = uquad_mat_load(Q,matrix);
    cleanup_if(retval);
       
    matrix = fopen("R","r"); 
    if(matrix == NULL)
    {
	err_log_stderr("fopen(R)");
	cleanup_if(ERROR_IO);
    }
    R = uquad_mat_alloc(4,4);
    retval = uquad_mat_load(R,matrix);
    cleanup_if(retval);

    phi = uquad_mat_alloc(A->r, A->c);
    gamma = uquad_mat_alloc(B->r, B->c);
    K = uquad_mat_alloc(4,12);

    retval = control_disc(phi,gamma,A,B,10e-3);
    cleanup_if(retval);
    retval = control_lqr(K,phi,gamma,Q,R);
    cleanup_if(retval);

    uquad_mat_dump(K,0);
    
    
    cleanup:
    uquad_mat_free(A);
    uquad_mat_free(B);
    uquad_mat_free(Q);
    uquad_mat_free(R);
    uquad_mat_free(phi);
    uquad_mat_free(gamma);
    uquad_mat_free(K);

    return retval;
    }
