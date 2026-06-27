#include "rstack.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <malloc.h>

typedef struct node node_t;
typedef struct rstack rstack_t;

struct rstack {   
    uint64_t ref_count; 
    bool seen; // used to mark it.
    node_t* top; // the element on the top of the stack.
    bool alive; // 0 iff rstack_delete was called on the rstack.
    // ptr to the previous or next element in the living/dead list
    // if alive == 1 it is in living, else it is in dead.
    rstack_t* prev; 
    rstack_t* next;
};

// represents an element of the stack
struct node {    
    enum {
        VALUE,
        STACK
    } type;
    union {
        uint64_t value;
        rstack_t* stack;
    } data;
    node_t* next; // ptr to the node below on the rstack.
};

// A list of rstacks that were deleted using rstack_delete.
rstack_t *dead = nullptr; 
// A list of rstacks that werent deleted using rstack_delete.
rstack_t *living = nullptr; 

void rstack_free(rstack_t *rs);

void dfs(rstack_t *rs) {
    if (rs->seen) {
        return;
    }
    rs->seen = 1;
    node_t *curr = rs->top;
    while (curr) {
        if (curr->type == STACK) {
            dfs(curr->data.stack);
        }
        curr = curr->next;
    }
}

void start_dfs() {
    // We do a mark a sweep to mark all the edges that can be 
    // reached from living rstacks.
    rstack_t *curr = living;
    while (curr) {
        dfs(curr);
        curr = curr->next;
    }
    // Cleaning up after the dfs and freeing memory on stacks 
    // that werent reached.
    curr = living;
    while (curr) {
        curr->seen = 0;
        curr = curr->next;
    }
    curr = dead;
    while (curr) {
        rstack_t *tmp = curr->next;
        if (!curr->seen) {
            rstack_free(curr);
        }
        else {
            curr->seen = 0;
        }
        curr = tmp;
    }
}

rstack_t *rstack_new() {
    rstack_t *rs = malloc(sizeof(rstack_t));
    if (!rs) {
        errno = ENOMEM;
        return nullptr;
    }
    if (living) {
        living->prev = rs;
    }
    rs->next = living;
    rs->prev = nullptr;
    living = rs;

    rs->ref_count = 1;
    rs->top = nullptr;
    rs->seen = 0;
    rs->alive = 1;
    return rs;
}

// Only this function free's rstack_t* and node_t*
void rstack_free(rstack_t *rs) {
    if (!rs) {
        return;
    }
    while (rs->top) {
        node_t *tmp = rs->top->next;
        // Calling rstack_free recursively on dead rstacks 
        // can lead to problems (due to cycles).
        if (rs->top->type == STACK && rs->alive) { 
            if (--rs->top->data.stack->ref_count == 0) {
                rstack_free(rs->top->data.stack);
            }
        }
        free(rs->top);
        rs->top = tmp;
    }
    // Fixing the living/dead list after deleting the rstack.
    if (rs->next) {
        rs->next->prev = rs->prev;
    }
    if (rs->prev) {
        rs->prev->next = rs->next;
    }
    else {
        if (rs->alive) {
            living = rs->next;
        }
        else {
            dead = rs->next;
        }
    }
    free(rs);
}

void rstack_delete(rstack_t *rs) {
    if (!rs) {
        return;
    }
    rs->ref_count--;
    if (rs->ref_count == 0) {
        rstack_free(rs);
    }
    else {
        // Fixing the living list after deleting this rstack from it.
        rs->alive = 0;
        if (rs->next) {
            rs->next->prev = rs->prev;
        }
        if (rs->prev) {
            rs->prev->next = rs->next;
        }
        else {
            living = rs->next;
        }
        // Placing rs on beginning of dead list.
        rs->next = dead;
        if (dead) {
            dead->prev = rs;
        }
        dead = rs;
        rs->prev = nullptr;
    }
    // Cleaning the dead rstacks (ondes that cant 
    // be reached from any living vertex).
    start_dfs();
}

int rstack_push_value(rstack_t *rs, uint64_t value) {
    if (!rs) {
        errno = EINVAL;
        return -1;
    }
    node_t *tmp = malloc(sizeof(node_t));
    if (!tmp) {
        errno = ENOMEM;
        return -1;
    }
    tmp->next = rs->top;
    rs->top = tmp;
    rs->top->type = VALUE;
    rs->top->data.value = value;
    return 0;
}

int rstack_push_rstack(rstack_t *rs1, rstack_t *rs2) {
    if (!rs1 || !rs2) {
        errno = EINVAL;
        return -1;
    }
    node_t *tmp = malloc(sizeof(node_t));
    if (!tmp) {
        errno = ENOMEM;
        return -1;
    }
    rs2->ref_count++;
    tmp->next = rs1->top;
    rs1->top = tmp;
    rs1->top->type = STACK;
    rs1->top->data.stack = rs2;
    return 0;
}

void rstack_pop(rstack_t *rs) {
    if (!rs || !rs->top) {
        return;
    }
    node_t *tmp = rs->top->next;
    if (rs->top->type == STACK && (--rs->top->data.stack->ref_count == 0)) {
        rstack_free(rs->top->data.stack);
    }
    free(rs->top);
    rs->top = tmp;
}


// Processess every rsatack at most once.
// looks for value recursively and if it finds it then it
// goes back the recursion tree to the caller (either
// rstack_empty of rstack_front) with the answer.
result_t _rstack_empty_front(rstack_t *rs, bool val) {
    result_t ans = {false, 0};
    if (!rs) {
        return ans;
    }
    if (rs->seen == val) {
        return ans;
    }
    rs->seen = val;
    node_t *curr = rs->top;
    while (curr) {
        if (curr->type == VALUE) {
            ans.flag = true, ans.value = curr->data.value;
            goto answer;
        } else
            ans = _rstack_empty_front(curr->data.stack, val);
        if (ans.flag) {
            goto answer;
        }
        curr = curr->next;
    }
answer:
    return ans;
}

bool rstack_empty(rstack_t *rs) {
    result_t ans = _rstack_empty_front(rs, 1);
    // Does exactly the same traversal as the one above and resets
    // rs->seen that were set to 1 back to 0.
    (void)_rstack_empty_front(rs, 0); 
    return !ans.flag;
}

result_t rstack_front(rstack_t *rs) {
    result_t ans = _rstack_empty_front(rs, 1);
    // Does exactly the same traversal as the one above and resets
    // rs->seen that were set to 1 back to 0.
    (void)_rstack_empty_front(rs, 0);       
    return ans;
}

rstack_t *rstack_read(char const *path) {
    if (!path) {
        errno = EINVAL;
        return nullptr;
    }
    FILE *f = fopen(path, "r");
    if (!f) {
        return nullptr; // errno set by fopen
    }
    rstack_t *rs = rstack_new();
    if (!rs) {
        fclose(f);
        errno = ENOMEM;
        return nullptr;
    }
    unsigned char buf[1024];
    // Flag is true if in num theres a number bein 
    // processed, num.value holds the number.
    result_t num = {0, 0}; 
    for (;;) {
        if(feof(f)) {
            break;
        }
        size_t n = fread(buf, 1, sizeof(buf), f);
        if (ferror(f)) {
            goto error;
        }
        for (size_t i = 0; i < n; ++i) {
            unsigned char c = buf[i];
            if (isspace(c)) {
                if (num.flag) {
                    int res = rstack_push_value(rs, num.value);
                    if (res == -1) {
                        goto error; // errno set by rstack_push_value
                    }
                }
                num.value = 0;
                num.flag = false;
                continue;
            }
            if (!isdigit(c)) {
                errno = EINVAL;
                goto error;
            }
            num.flag = true;
            int digit = c - '0';
            if (num.value > (UINT64_MAX - digit) / 10) {
                errno = ERANGE;
                goto error;
            }
            num.value = num.value * 10 + digit;
        }
    }
    if (num.flag) {
        int res = rstack_push_value(rs, num.value);
        if (res == -1) {
            goto error; // errno set by rstack_push_value
        }
    }
    if(fclose(f)) {
        rstack_free(rs);
        return nullptr;
    }
    return rs;
error:
    fclose(f); 
    rstack_free(rs);
    return nullptr;
}

int _rstack_write(FILE *f, rstack_t *rs);

// Returns 1 if cycle is deteced, -1 if an error occured and 0 otherwise
// writes out the contents of nodes from bottom to top and
// writes the value if it holds a value, else calls recursively
// one _rstack_write.
int node_write(FILE *f, node_t *node) {
    if (!node) {
        return 0;
    }
    int res = node_write(f, node->next);
    if (res) {
        return res;
    }
    // We know theres no cycle and no error up until now
    if (node->type == STACK) {
        return _rstack_write(f, node->data.stack);
    }
    // It's a VALUE.
    if (fprintf(f, "%" PRIu64 "\n", node->data.value) < 0) {
        return -1;
    }
    if (fflush(f) != 0) {
        return -1;
    }
    if(ferror(f)) {
        return -1;
    }
    return 0;
}

// Returns 1 iff cycle is detected, else returns what node_write returned.
// writes out the contents of the rstack from bottom to top.
int _rstack_write(FILE *f, rstack_t *rs) {
    if (rs->seen) {
        return 1;
    }
    rs->seen = 1;
    int res = node_write(f, rs->top);
    rs->seen = 0;
    return res;
}

int rstack_write(char const *path, rstack_t *rs) {
    if (!rs || !path) { //
        errno = EINVAL;
        return -1;
    }
    FILE *f = fopen(path, "w");
    if (!f) {
        return -1; // errno set by fopen
    }
    int res = _rstack_write(f, rs);
    if (ferror(f)) {
        res = -1;
    }
    if(fclose(f)) {
        res = -1;
    }
    return (res == -1 ? -1 : 0); // if res == 1 we still return 0.
}
